import { useRef, useState, useEffect, useCallback } from 'react';

interface SignatureCanvasProps {
  onSave: (base64PNG: string) => void;
  width?: number;
  height?: number;
}

export default function SignatureCanvas({ onSave, width = 400, height = 150 }: SignatureCanvasProps) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [isDrawing, setIsDrawing] = useState(false);
  const [hasSignature, setHasSignature] = useState(false);
  const strokeCountRef = useRef(0);
  const MIN_STROKES = 2; // Minimum number of strokes for a valid signature (eIDAS)

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    ctx.strokeStyle = '#0F172A';
  }, []);

  const getPos = useCallback((e: React.MouseEvent | React.TouchEvent) => {
    const canvas = canvasRef.current;
    if (!canvas) return { x: 0, y: 0 };
    const rect = canvas.getBoundingClientRect();
    const scaleX = canvas.width / rect.width;
    const scaleY = canvas.height / rect.height;
    if ('touches' in e) {
      const touch = e.touches[0];
      return { x: (touch.clientX - rect.left) * scaleX, y: (touch.clientY - rect.top) * scaleY };
    }
    return { x: (e.clientX - rect.left) * scaleX, y: (e.clientY - rect.top) * scaleY };
  }, []);

  const startDraw = useCallback((e: React.MouseEvent | React.TouchEvent) => {
    e.preventDefault();
    const ctx = canvasRef.current?.getContext('2d');
    if (!ctx) return;
    const { x, y } = getPos(e);
    ctx.beginPath();
    ctx.moveTo(x, y);
    setIsDrawing(true);
  }, [getPos]);

  const draw = useCallback((e: React.MouseEvent | React.TouchEvent) => {
    if (!isDrawing) return;
    e.preventDefault();
    const ctx = canvasRef.current?.getContext('2d');
    if (!ctx) return;
    const { x, y } = getPos(e);
    ctx.lineTo(x, y);
    ctx.stroke();
    setHasSignature(true);
  }, [isDrawing, getPos]);

  const endDraw = useCallback(() => {
    setIsDrawing(false);
  }, []);

  const clear = () => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    setHasSignature(false);
  };

  const save = () => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const base64 = canvas.toDataURL('image/png');
    onSave(base64);
  };

  return (
    <div className="border-2 border-dashed border-border rounded-lg p-2 bg-background">
      <p className="text-xs text-muted-foreground mb-1">Signez ci-dessous avec votre souris ou votre doigt :</p>
      <canvas
        ref={canvasRef}
        width={width}
        height={height}
        className="border border-border rounded cursor-crosshair touch-none w-full bg-background"
        style={{ height: `${height}px` }}
        onMouseDown={startDraw}
        onMouseMove={draw}
        onMouseUp={endDraw}
        onMouseLeave={endDraw}
        onTouchStart={startDraw}
        onTouchMove={draw}
        onTouchEnd={endDraw}
      />
      <div className="flex gap-2 mt-2">
        <button type="button" onClick={clear} className="text-xs text-muted-foreground underline">Effacer</button>
        <button
          type="button"
          onClick={save}
          disabled={!hasSignature}
          className="text-xs bg-primary text-primary-foreground px-3 py-1 rounded disabled:opacity-50"
        >
          Valider la signature
        </button>
      </div>
    </div>
  );
}
