import { useEffect, useMemo } from 'react';
import { StyleSheet, Text, View } from 'react-native';
import type { ContractRevision, VerifiedContractOriginal } from '../../workflows/contracts/types';
import { ErrorNotice } from '../components';
import { parseNativeContract } from './readerModel';

export interface ContractOriginalReaderProps {
  original: VerifiedContractOriginal;
  /** Confirms complete supported rendering, never that the user has read/accepted it. */
  onPresented: (revision: ContractRevision) => void;
  onUnavailable: (revision: ContractRevision, message: string) => void;
}
export function ContractOriginalReader({ original, onPresented, onUnavailable }: ContractOriginalReaderProps) {
  const document = useMemo(() => parseNativeContract(original.html), [original.html]);
  const revision = useMemo(() => ({ contractId: original.contractId, sha256: original.sha256, storagePath: original.storagePath }),
    [original.contractId, original.sha256, original.storagePath]);
  useEffect(() => { if (!document.supported) onUnavailable(revision, document.reason); }, [document, onUnavailable, revision]);
  if (!document.supported) return <ErrorNotice message={document.reason} />;
  return <View style={styles.document} testID="contract-original" onLayout={() => onPresented(revision)}>
    {document.blocks.map((block, index) => <View key={index} style={block.kind === 'notice' ? styles.notice : undefined}>
      <Text selectable accessibilityRole={block.kind === 'h1' || block.kind === 'h2' ? 'header' : 'text'}
        testID={index === document.blocks.length - 1 ? 'contract-original-end' : `contract-block-${index}`} style={[styles.text,
          block.kind === 'h1' && styles.h1, block.kind === 'h2' && styles.h2, block.kind === 'pre' && styles.pre]}>
        {block.runs.map((run, runIndex) => <Text key={runIndex} style={[run.bold && styles.bold, run.italic && styles.italic]}>{run.text}</Text>)}
      </Text>
    </View>)}
  </View>;
}
const styles = StyleSheet.create({
  document: { padding: 20, borderRadius: 18, backgroundColor: '#FFFFFF', borderWidth: 1, borderColor: '#E9E1ED' },
  text: { fontSize: 16, lineHeight: 26, color: '#0F172A', marginVertical: 8, flexShrink: 1 },
  h1: { fontSize: 22, lineHeight: 31, fontWeight: '700', color: '#D6336C', borderBottomColor: '#FCE7F3', borderBottomWidth: 2, paddingBottom: 8 },
  h2: { fontSize: 18, lineHeight: 27, fontWeight: '700', color: '#4B1D3A', marginTop: 24 },
  bold: { fontWeight: '700', color: '#1E293B' }, italic: { fontStyle: 'italic', color: '#64748B' },
  pre: { fontSize: 16, lineHeight: 26 }, notice: { backgroundColor: '#FEF3F7', borderLeftColor: '#D6336C', borderLeftWidth: 4, paddingHorizontal: 16, paddingVertical: 12, marginBottom: 24 },
});
