import React, { useRef, useState } from 'react';
import { Camera, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';
import { IMAGE_DOCUMENT_MIME_TYPES, verifierFichierDocument } from '@/lib/documentUpload';

const FALLBACK_COLORS = [
  'hsl(var(--primary))',        // teal
  'hsl(243 75% 59%)',           // indigo
  'hsl(330 81% 60%)',           // rose
  'hsl(38 92% 50%)',            // amber
  'hsl(152 69% 41%)',           // emerald
  'hsl(263 70% 58%)',           // violet
];

function hashName(name: string): number {
  let h = 0;
  for (let i = 0; i < name.length; i++) h = ((h << 5) - h + name.charCodeAt(i)) | 0;
  return Math.abs(h);
}

function getInitials(prenom?: string, nom?: string): string {
  return ((prenom?.[0] || '') + (nom?.[0] || '')).toUpperCase() || '?';
}

function getFallbackColor(name: string): string {
  return FALLBACK_COLORS[hashName(name) % FALLBACK_COLORS.length];
}

async function compressImage(file: File): Promise<Blob> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    const objectUrl = URL.createObjectURL(file);
    img.onload = () => {
      URL.revokeObjectURL(objectUrl);
      const MAX = 256;
      let w = img.width, h = img.height;
      if (w > h) { if (w > MAX) { h = (h * MAX) / w; w = MAX; } }
      else { if (h > MAX) { w = (w * MAX) / h; h = MAX; } }
      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext('2d');
      if (!ctx) { reject(new Error('Compression failed')); return; }
      ctx.drawImage(img, 0, 0, w, h);
      canvas.toBlob(
        (blob) => blob ? resolve(blob) : reject(new Error('Compression failed')),
        'image/webp',
        0.8
      );
    };
    img.onerror = () => {
      URL.revokeObjectURL(objectUrl);
      reject(new Error('Image illisible'));
    };
    img.src = objectUrl;
  });
}

/* ── Display-only avatar (no upload) ── */

interface AvatarDisplayProps {
  src?: string | null;
  prenom?: string;
  nom?: string;
  size?: number;
  rounded?: 'full' | 'lg';
  className?: string;
}

export function AvatarDisplay({ src, prenom, nom, size = 40, rounded = 'full', className = '' }: AvatarDisplayProps) {
  const initials = getInitials(prenom, nom);
  const bg = getFallbackColor((prenom || '') + (nom || ''));
  const r = rounded === 'full' ? 'rounded-full' : 'rounded-xl';
  const fontSize = size >= 64 ? 'text-2xl' : size >= 32 ? 'text-sm' : 'text-xs';

  return (
    <div
      className={`shrink-0 flex items-center justify-center overflow-hidden ${r} ${className}`}
      style={{ width: size, height: size, backgroundColor: src ? undefined : bg }}
    >
      {src ? (
        <img src={src} alt={`${prenom || ''} ${nom || ''}`} className={`w-full h-full object-cover ${r}`} loading="lazy" />
      ) : (
        <span className={`font-bold text-white select-none ${fontSize}`}>{initials}</span>
      )}
    </div>
  );
}

/* ── Upload avatar ── */

interface AvatarUploadProps {
  src?: string | null;
  prenom?: string;
  nom?: string;
  size?: number;
  /** 'soignant' stores in avatar_url, 'etablissement' stores in logo_url */
  mode: 'soignant' | 'etablissement';
  onUploaded?: (url: string) => void;
}

export function AvatarUpload({ src, prenom, nom, size = 96, mode, onUploaded }: AvatarUploadProps) {
  const { user } = useAuth();
  const inputRef = useRef<HTMLInputElement>(null);
  const [uploading, setUploading] = useState(false);
  const [currentSrc, setCurrentSrc] = useState(src);

  const rounded = mode === 'etablissement' ? 'lg' : 'full';
  const r = rounded === 'full' ? 'rounded-full' : 'rounded-xl';
  const initials = getInitials(prenom, nom);
  const bg = getFallbackColor((prenom || '') + (nom || ''));
  const fontSize = size >= 64 ? 'text-2xl' : 'text-sm';

  const handleFile = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file || !user) return;
    const validation = await verifierFichierDocument(file, {
      maxBytes: 2 * 1024 * 1024,
      allowedMimes: IMAGE_DOCUMENT_MIME_TYPES,
    });
    if (validation.ok === false) {
      toast.error(validation.message);
      e.target.value = '';
      return;
    }

    setUploading(true);
    try {
      const compressed = await compressImage(file);
      const assetPrefix = mode === 'soignant' ? 'avatar' : 'logo';
      const path = `${user.id}/${assetPrefix}-${Date.now()}.webp`;

      const { error: uploadErr } = await supabase.storage
        .from('jolene-documents')
        .upload(path, compressed, { contentType: 'image/webp', upsert: false });
      if (uploadErr) throw uploadErr;

      const { data: urlData } = await supabase.storage
        .from('jolene-documents')
        // avatar_url/logo_url sont consommés directement par les listes et la
        // messagerie. Une URL d'une heure cassait donc l'image dès le lendemain.
        // Le jeton reste limité à cet avatar (jamais aux autres documents).
        .createSignedUrl(path, 5 * 365 * 24 * 60 * 60);

      const signedUrl = urlData?.signedUrl;
      if (!signedUrl) throw new Error('URL generation failed');

      if (mode === 'soignant') {
        const { error } = await supabase.rpc('fn_modifier_mon_profil', { p_avatar_url: signedUrl });
        if (error) throw error;
      } else {
        const { error } = await supabase.rpc('fn_modifier_mon_etablissement', { p_logo_url: signedUrl });
        if (error) throw error;
      }

      setCurrentSrc(signedUrl);
      onUploaded?.(signedUrl);
      toast.success('Photo mise à jour !');
    } catch (err: any) {
      toast.error('Une erreur est survenue lors de l\'upload. Veuillez réessayer.');
    } finally {
      setUploading(false);
      if (inputRef.current) inputRef.current.value = '';
    }
  };

  return (
    <div className="relative shrink-0" style={{ width: size, height: size }}>
      <button
        type="button"
        onClick={() => inputRef.current?.click()}
        disabled={uploading}
        aria-label={mode === 'soignant' ? 'Changer ma photo de profil' : 'Changer le logo de l\'établissement'}
        className={`relative group w-full h-full ${r} overflow-hidden focus:outline-none focus-visible:ring-2 focus-visible:ring-ring`}
      >
        {/* Image or initials */}
        <div
          className={`w-full h-full flex items-center justify-center ${r}`}
          style={{ backgroundColor: currentSrc ? undefined : bg }}
        >
          {currentSrc ? (
            <img src={currentSrc} alt="" className={`w-full h-full object-cover ${r}`} />
          ) : (
            <span className={`font-bold text-white select-none ${fontSize}`}>{initials}</span>
          )}
        </div>

        {/* Overlay */}
        {uploading ? (
          <div aria-hidden="true" className={`absolute inset-0 flex items-center justify-center bg-black/50 ${r}`}>
            <Loader2 className="h-6 w-6 text-white animate-spin" />
          </div>
        ) : (
          <div aria-hidden="true" className={`absolute inset-0 flex items-center justify-center bg-black/0 group-hover:bg-black/40 transition-colors ${r}`}>
            <Camera className="h-5 w-5 text-white opacity-0 group-hover:opacity-100 transition-opacity" />
          </div>
        )}
      </button>

      <input
        ref={inputRef}
        type="file"
        accept="image/png,image/jpeg,image/webp"
        onChange={handleFile}
        className="hidden"
        aria-hidden="true"
      />
    </div>
  );
}
