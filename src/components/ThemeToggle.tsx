import { Moon, Sun } from 'lucide-react';
import { useTheme } from '@/hooks/useTheme';

export function ThemeToggle({ className = '' }: { className?: string }) {
  const { theme, toggleTheme } = useTheme();

  return (
    <button
      onClick={toggleTheme}
      aria-label={theme === 'dark' ? 'Passer en mode clair' : 'Passer en mode sombre'}
      className={`p-2 rounded-lg transition-colors hover:bg-accent ${className}`}
    >
      {theme === 'dark' ? (
        <Sun className="h-5 w-5 text-warning" />
      ) : (
        <Moon className="h-5 w-5 text-muted-foreground" />
      )}
    </button>
  );
}
