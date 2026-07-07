import type { Config } from 'tailwindcss';

export default {
  content: ['./index.html', './src/**/*.{ts,tsx}'],
  theme: {
    extend: {
      colors: {
        background: '#FFFFFF',
        foreground: '#000000',
        primary: '#2563EB',
        card: '#F2F2F7',
        secondary: '#8E8E93',
        success: '#34C759',
        error: '#FF453A',
        warning: '#FF9F0A',
        selected: 'rgba(37, 99, 235, 0.1)',
      },
      borderColor: {
        DEFAULT: 'rgba(0, 0, 0, 0.1)',
      },
      fontFamily: {
        sans: ['"DM Sans"', 'system-ui', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'ui-monospace', 'monospace'],
      },
      spacing: {
        xs: '4px',
        sm: '8px',
        md: '12px',
        lg: '16px',
        xl: '24px',
        xxl: '32px',
      },
      borderRadius: {
        card: '10px',
        button: '14px',
        chip: '8px',
        xl: '16px',
      },
    },
  },
  plugins: [],
} satisfies Config;