/**
 * The CCE mark: "CCE" in white with a Sunbeam period, set as live text.
 * PLACEHOLDER until a final logo file is confirmed. When it is, replace the
 * text below with the file (keep the Stage tile on light backgrounds).
 */
export function BrandMark({ className = "" }: { className?: string }) {
  return (
    <span
      className={`inline-flex items-center rounded-chip bg-stage px-3 py-1.5 font-sans text-xl font-extrabold tracking-tight text-paper ${className}`}
      aria-label="CCE"
    >
      CCE<span className="text-sunbeam" aria-hidden="true">.</span>
    </span>
  );
}
