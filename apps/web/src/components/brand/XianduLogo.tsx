interface XianduLogoProps {
  className?: string;
  decorative?: boolean;
  title?: string;
  variant?: "main" | "page";
}

export function XianduLogo({
  className,
  decorative = false,
  title = "衔牍",
  variant = "main"
}: XianduLogoProps) {
  const src = variant === "page" ? "/brand/xiandu-page-logo.png" : "/brand/xiandu-main-logo.png";

  return (
    <img
      alt={decorative ? "" : title}
      aria-hidden={decorative || undefined}
      className={className}
      draggable={false}
      src={src}
    />
  );
}
