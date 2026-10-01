#!/usr/bin/env node
// Offline only. Decryption is not approval and never executes the recovered DDL.
import {readFileSync,writeFileSync,mkdirSync,existsSync,statSync} from 'node:fs';import {resolve} from 'node:path';import {fileURLToPath} from 'node:url';
import {createPrivateKey,createPublicKey,createHash,privateDecrypt,createDecipheriv,constants} from 'node:crypto';import {rejectKnownSecrets} from './export-schema.mjs';
const hash=b=>createHash('sha256').update(b).digest('hex'),fail=()=>{throw Error('QUARANTINE_REFUSED')};
export function decryptQuarantine(e,pem,recipientHash){
 if(!e||Object.keys(e).sort().join()!=='cipher,ciphertext,format,iv,key_wrap,tag,wrapped_key'||e.format!=='JOLENE_DDL_ENCRYPTED_V1'||e.cipher!=='AES-256-GCM'||e.key_wrap!=='RSA-OAEP-SHA256'||!/^([a-f0-9]{64})$/.test(recipientHash??''))fail();
 const from64=(s,n)=>{if(typeof s!=='string'||s.length>140*1024*1024||!/^[A-Za-z0-9+/]+={0,2}$/.test(s))fail();const b=Buffer.from(s,'base64');if(b.toString('base64')!==s||(n&&b.length!==n))fail();return b};
 const privateKey=createPrivateKey(pem),publicKey=createPublicKey(privateKey);if(publicKey.asymmetricKeyType!=='rsa'||publicKey.asymmetricKeyDetails.modulusLength!==4096||hash(publicKey.export({type:'spki',format:'der'}))!==recipientHash)fail();
 const secret=privateDecrypt({key:privateKey,oaepHash:'sha256',padding:constants.RSA_PKCS1_OAEP_PADDING},from64(e.wrapped_key,512));
 let value;try{const d=createDecipheriv('aes-256-gcm',secret,from64(e.iv,12));d.setAuthTag(from64(e.tag,16));value=JSON.parse(Buffer.concat([d.update(from64(e.ciphertext)),d.final()]))}finally{secret.fill(0)}
 const names=['all.private.sql','application.private.sql','customizations.private.sql','managed-acl-review.private.sql','manifest.json'];
 if(value?.format!=='JOLENE_DDL_QUARANTINE_V1'||Object.keys(value.files??{}).sort().join()!==names.sort().join())fail();
 const files={};for(const name of names){const b=from64(value.files[name]);if(b.length>32*1024*1024)fail();rejectKnownSecrets(b.toString());files[name]=b;}
 const manifest=JSON.parse(files['manifest.json']);if(manifest.result!=='DDL_QUARANTINED_ONLY'||manifest.release_authorized!==false||manifest.import_ready!==false)fail();
 for(const name of names.filter(n=>n.endsWith('.sql')))if(manifest.files?.[name]?.sha256!==hash(files[name])||manifest.files[name].bytes!==files[name].length)fail();
 return files;
}
if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url))try{
 if(process.argv.length!==7)fail();const [encryptedPath,keyPath,expectedEnvelopeHash,recipientHash,outputDir]=process.argv.slice(2);
 if(existsSync(outputDir)||(statSync(keyPath).mode&0o077)!==0||!/^[a-f0-9]{64}$/.test(expectedEnvelopeHash))fail();
 const encrypted=readFileSync(encryptedPath);if(encrypted.length>140*1024*1024||hash(encrypted)!==expectedEnvelopeHash)fail();
 const files=decryptQuarantine(JSON.parse(encrypted),readFileSync(keyPath),recipientHash);process.umask(0o077);mkdirSync(outputDir,{mode:0o700});
 for(const [name,b]of Object.entries(files))writeFileSync(resolve(outputDir,name),b,{mode:0o600,flag:'wx'});
 console.log(JSON.stringify({result:'DECRYPTED_QUARANTINE_ONLY',files:Object.fromEntries(Object.entries(files).map(([name,b])=>[name,{sha256:hash(b),bytes:b.length}])),release_authorized:false,import_ready:false}));
}catch{console.error(JSON.stringify({result:'REFUSED',code:'QUARANTINE_REFUSED'}));process.exitCode=1}
