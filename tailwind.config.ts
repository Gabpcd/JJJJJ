import type { Config } from "tailwindcss";
import tailwindcssAnimate from "tailwindcss-animate";

export default {
  darkMode: ["class"],
  content: ["./pages/**/*.{ts,tsx}", "./components/**/*.{ts,tsx}", "./app/**/*.{ts,tsx}", "./src/**/*.{ts,tsx}"],
  prefix: "",
  theme: {
    container: {
      center: true,
      padding: "2rem",
      screens: {
        "2xl": "1400px",
      },
    },
    extend: {
      fontFamily: {
        sans: ['Inter', 'system-ui', '-apple-system', 'sans-serif'],
      },
      colors: {
        border: "hsl(var(--border))",
        input: "hsl(var(--input))",
        ring: "hsl(var(--ring))",
        background: "hsl(var(--background))",
        foreground: "hsl(var(--foreground))",
        primary: {
          DEFAULT: "hsl(var(--primary))",
          foreground: "hsl(var(--primary-foreground))",
          dark: "hsl(var(--primary-dark))",
          light: "hsl(var(--primary-light))",
        },
        rose: {
          DEFAULT: "hsl(var(--rose))",
          foreground: "hsl(var(--rose-foreground))",
          light: "hsl(var(--rose-light))",
        },
        teal: {
          DEFAULT: "hsl(var(--teal))",
          foreground: "hsl(var(--teal-foreground))",
        },
        secondary: {
          DEFAULT: "hsl(var(--secondary))",
          foreground: "hsl(var(--secondary-foreground))",
        },
        destructive: {
          DEFAULT: "hsl(var(--destructive))",
          foreground: "hsl(var(--destructive-foreground))",
        },
        muted: {
          DEFAULT: "hsl(var(--muted))",
          foreground: "hsl(var(--muted-foreground))",
        },
        accent: {
          DEFAULT: "hsl(var(--accent))",
          foreground: "hsl(var(--accent-foreground))",
          navy: "hsl(var(--accent-navy))",
        },
        popover: {
          DEFAULT: "hsl(var(--popover))",
          foreground: "hsl(var(--popover-foreground))",
        },
        card: {
          DEFAULT: "hsl(var(--card))",
          foreground: "hsl(var(--card-foreground))",
        },
        success: {
          DEFAULT: "hsl(var(--success))",
          foreground: "hsl(var(--success-foreground))",
        },
        warning: {
          DEFAULT: "hsl(var(--warning))",
          foreground: "hsl(var(--warning-foreground))",
        },
        info: {
          DEFAULT: "hsl(var(--info))",
          foreground: "hsl(var(--info-foreground))",
        },
        sidebar: {
          DEFAULT: "hsl(var(--sidebar-background))",
          foreground: "hsl(var(--sidebar-foreground))",
          primary: "hsl(var(--sidebar-primary))",
          "primary-foreground": "hsl(var(--sidebar-primary-foreground))",
          accent: "hsl(var(--sidebar-accent))",
          "accent-foreground": "hsl(var(--sidebar-accent-foreground))",
          border: "hsl(var(--sidebar-border))",
          ring: "hsl(var(--sidebar-ring))",
        },
        /* Sprint 9-A — Palette Y2K Gen Z (additive, non-breaking)
         * Usage : bg-jolene-rose, text-jolene-mauve-700, border-jolene-cyan-300, etc. */
        "jolene-rose": {
          DEFAULT: "hsl(var(--jolene-rose))",
          50: "hsl(var(--jolene-rose-50))",
          100: "hsl(var(--jolene-rose-100))",
          200: "hsl(var(--jolene-rose-200))",
          300: "hsl(var(--jolene-rose-300))",
          400: "hsl(var(--jolene-rose-400))",
          500: "hsl(var(--jolene-rose-500))",
          600: "hsl(var(--jolene-rose-600))",
          700: "hsl(var(--jolene-rose-700))",
          800: "hsl(var(--jolene-rose-800))",
          900: "hsl(var(--jolene-rose-900))",
        },
        "jolene-mauve": {
          DEFAULT: "hsl(var(--jolene-mauve))",
          50: "hsl(var(--jolene-mauve-50))",
          100: "hsl(var(--jolene-mauve-100))",
          200: "hsl(var(--jolene-mauve-200))",
          300: "hsl(var(--jolene-mauve-300))",
          400: "hsl(var(--jolene-mauve-400))",
          500: "hsl(var(--jolene-mauve-500))",
          600: "hsl(var(--jolene-mauve-600))",
          700: "hsl(var(--jolene-mauve-700))",
          800: "hsl(var(--jolene-mauve-800))",
          900: "hsl(var(--jolene-mauve-900))",
        },
        "jolene-cyan": {
          DEFAULT: "hsl(var(--jolene-cyan))",
          50: "hsl(var(--jolene-cyan-50))",
          100: "hsl(var(--jolene-cyan-100))",
          200: "hsl(var(--jolene-cyan-200))",
          300: "hsl(var(--jolene-cyan-300))",
          400: "hsl(var(--jolene-cyan-400))",
          500: "hsl(var(--jolene-cyan-500))",
          600: "hsl(var(--jolene-cyan-600))",
          700: "hsl(var(--jolene-cyan-700))",
          800: "hsl(var(--jolene-cyan-800))",
          900: "hsl(var(--jolene-cyan-900))",
        },
        "jolene-butter": {
          DEFAULT: "hsl(var(--jolene-butter))",
          50: "hsl(var(--jolene-butter-50))",
          100: "hsl(var(--jolene-butter-100))",
          200: "hsl(var(--jolene-butter-200))",
          300: "hsl(var(--jolene-butter-300))",
          400: "hsl(var(--jolene-butter-400))",
          500: "hsl(var(--jolene-butter-500))",
          600: "hsl(var(--jolene-butter-600))",
          700: "hsl(var(--jolene-butter-700))",
          800: "hsl(var(--jolene-butter-800))",
          900: "hsl(var(--jolene-butter-900))",
        },
        "jolene-lavender": "hsl(var(--jolene-lavender))",
        "jolene-cloud": "hsl(var(--jolene-cloud))",
        "jolene-midnight": "hsl(var(--jolene-midnight))",
        "jolene-bubblegum": "hsl(var(--jolene-bubblegum))",
      },
      borderRadius: {
        lg: "var(--radius)",
        md: "calc(var(--radius) - 2px)",
        sm: "calc(var(--radius) - 4px)",
        xl: "1rem",
        "2xl": "1.25rem",
      },
      keyframes: {
        "accordion-down": {
          from: { height: "0" },
          to: { height: "var(--radix-accordion-content-height)" },
        },
        "accordion-up": {
          from: { height: "var(--radix-accordion-content-height)" },
          to: { height: "0" },
        },
        shimmer: {
          "0%": { backgroundPosition: "-200% 0" },
          "100%": { backgroundPosition: "200% 0" },
        },
        "fade-in": {
          from: { opacity: "0" },
          to: { opacity: "1" },
        },
      },
      animation: {
        "accordion-down": "accordion-down 0.2s ease-out",
        "accordion-up": "accordion-up 0.2s ease-out",
        shimmer:
          "shimmer 1.6s linear infinite, fade-in 200ms ease-out",
        "fade-in": "fade-in 200ms ease-out",
      },
      backgroundImage: {
        shimmer:
          "linear-gradient(90deg, hsl(var(--muted)) 0%, hsl(var(--muted-foreground) / 0.08) 50%, hsl(var(--muted)) 100%)",
      },
      backgroundSize: {
        "shimmer-2x": "200% 100%",
      },
    },
  },
  plugins: [tailwindcssAnimate],
} satisfies Config;
