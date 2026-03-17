import React, { useRef, useState } from 'react';
import { Camera, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';

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
    img.onload = () => {
      const MAX = 256;
      let w = img.width, h = img.height;
      if (w > h) { if (w > MAX) { h = (h * MAX) / w; w = MAX; } }
      else { if (h > MAX) { w = (w * MAX) / h; h = MAX; } }
      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext('2d')!;
      ctx.drawImage(img, 0, 0, w, h);
      canvas.toBlob(
        (blob) => blob ? resolve(blob) : reject(new Error('Compression failed')),
        'image/webp',
        0.8
      );
    };
    img.onerror = reject;
    img.src = URL.createObjectURL(file);
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
    if (file.size > 2 * 1024 * 1024) {
      toast.error('Image trop lourde (max 2 Mo).');
      return;
    }

    setUploading(true);
    try {
      const compressed = await compressImage(file);
      const path = `${user.id}/avatar.webp`;

      const { error: uploadErr } = await supabase.storage
        .from('jolene-documents')
        .upload(path, compressed, { contentType: 'image/webp', upsert: true });
      if (uploadErr) throw uploadErr;

      const { data: urlData } = await supabase.storage
        .from('jolene-documents')
        .createSignedUrl(path, 60 * 60 * 24 * 365); // 1 year

      const signedUrl = urlData?.signedUrl;
      if (!signedUrl) throw new Error('URL generation failed');

      if (mode === 'soignant') {
        await supabase.rpc('fn_modifier_mon_profil' as any, { p_avatar_url: signedUrl });
      } else {
        await supabase.rpc('fn_modifier_mon_etablissement' as any, { p_logo_url: signedUrl });
      }

      setCurrentSrc(signedUrl);
      onUploaded?.(signedUrl);
      toast.success('Photo mise à jour !');
    } catch (err: any) {
      toast.error(err.message || 'Erreur lors de l\'upload.');
    } finally {
      setUploading(false);
      if (inputRef.current) inputRef.current.value = '';
    }
  };

  return (
    <button
      type="button"
      onClick={() => inputRef.current?.click()}
      disabled={uploading}
      aria-label={mode === 'soignant' ? 'Changer ma photo de profil' : 'Changer le logo de l\'établissement'}
      className={`relative group shrink-0 ${r} overflow-hidden focus:outline-none focus-visible:ring-2 focus-visible:ring-ring`}
      style={{ width: size, height: size }}
    >
      {/* Image or initials */}
      <div
        className={`w-full h-full flex items-center justify-center ${r}`}
        style={{ backgroundColor: currentSrc ? undefined : bg }}
      >
        {currentSrc ? (
          <img src={currentSrc} alt="Avatar" className={`w-full h-full object-cover ${r}`} />
        ) : (
          <span className={`font-bold text-white select-none ${fontSize}`}>{initials}</span>
        )}
      </div>

      {/* Overlay */}
      {uploading ? (
        <div className={`absolute inset-0 flex items-center justify-center bg-black/50 ${r}`}>
          <Loader2 className="h-6 w-6 text-white animate-spin" />
        </div>
      ) : (
        <div className={`absolute inset-0 flex items-center justify-center bg-black/0 group-hover:bg-black/40 transition-colors ${r}`}>
          <Camera className="h-5 w-5 text-white opacity-0 group-hover:opacity-100 transition-opacity" />
        </div>
      )}

      <input
        ref={inputRef}
        type="file"
        accept="image/png,image/jpeg,image/webp"
        onChange={handleFile}
        className="hidden"
        aria-hidden="true"
      />
    </button>
  );
}
