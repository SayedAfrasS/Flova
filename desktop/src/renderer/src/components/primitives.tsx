import { ButtonHTMLAttributes, forwardRef } from "react";

export function FlovaMark({ size = 26 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" fill="none" aria-hidden="true">
      <defs>
        <linearGradient id="flova-g" x1="4" y1="28" x2="28" y2="4" gradientUnits="userSpaceOnUse">
          <stop stopColor="#2563EB" /><stop offset="1" stopColor="#6366F1" />
        </linearGradient>
      </defs>
      {/* broken ring = two flows meeting; final brand SVG swaps in later */}
      <path d="M4.5 16a11.5 11.5 0 0 1 11.5-11.5" stroke="url(#flova-g)" strokeWidth="4" strokeLinecap="round" />
      <path d="M27.5 16A11.5 11.5 0 0 1 16 27.5" stroke="url(#flova-g)" strokeWidth="4" strokeLinecap="round" opacity=".55" />
    </svg>
  );
}

type Variant = "primary" | "secondary" | "ghost";
type Props = ButtonHTMLAttributes<HTMLButtonElement> & { variant?: Variant };

const styles: Record<Variant, string> = {
  primary:   "bg-accent text-white hover:bg-accent-hover border border-transparent",
  secondary: "bg-canvas text-ink border border-line hover:bg-surface",
  ghost:     "bg-transparent text-ink-2 border border-transparent hover:bg-section hover:text-ink",
};

export const Button = forwardRef<HTMLButtonElement, Props>(
  ({ variant = "primary", className = "", ...props }, ref) => (
    <button
      ref={ref}
      className={`h-11 px-5 rounded-control text-[14px] font-medium transition-colors duration-150
        focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent
        ${styles[variant]} ${className}`}
      {...props}
    />
  ),
);
Button.displayName = "Button";