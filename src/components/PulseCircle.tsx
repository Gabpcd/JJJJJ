import React, { useEffect, useState } from 'react';

interface PulseCircleProps {
  active: boolean;
  color?: string;
}

export function PulseCircle({ active, color = 'bg-success' }: PulseCircleProps) {
  const [show, setShow] = useState(false);

  useEffect(() => {
    if (active) {
      setShow(true);
      const timer = setTimeout(() => setShow(false), 2400);
      return () => clearTimeout(timer);
    }
  }, [active]);

  if (!show) return null;

  return (
    <div className="flex items-center justify-center my-3" aria-hidden="true">
      <div className={`h-10 w-10 rounded-full ${color} pulse-ring-animation`} />
    </div>
  );
}
