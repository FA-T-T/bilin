interface BilinLogoProps {
  className?: string;
  decorative?: boolean;
  title?: string;
  variant?: "main" | "page";
  wordmark?: string;
}

const LOGO_SRC = "/brand/bilin-image2-logo-512.png";

export function BilinLogo({
  className,
  decorative = false,
  title = "Bilin",
  variant = "main",
  wordmark = "Bilin"
}: BilinLogoProps) {
  const classNames = ["bilin-logo", className].filter(Boolean).join(" ");
  const isPageLogo = variant === "page";

  return (
    <svg
      aria-hidden={decorative || undefined}
      aria-label={decorative ? undefined : title}
      className={classNames}
      data-variant={variant}
      focusable="false"
      height="64"
      role={decorative ? undefined : "img"}
      viewBox={isPageLogo ? "0 0 188 64" : "0 0 64 64"}
      width={isPageLogo ? "188" : "64"}
      xmlns="http://www.w3.org/2000/svg"
    >
      <image
        className="bilin-logo__mark-image"
        height={isPageLogo ? "58" : "64"}
        href={LOGO_SRC}
        preserveAspectRatio="xMidYMid meet"
        width={isPageLogo ? "58" : "64"}
        x={isPageLogo ? "3" : "0"}
        y={isPageLogo ? "3" : "0"}
      />

      {isPageLogo ? (
        <g className="bilin-logo__wordmark">
          <text className="bilin-logo__wordmark-text" x="76" y="38">
            {wordmark}
          </text>
          <path className="bilin-logo__wordmark-line" d="M77 47.7h88" stroke="currentColor" />
        </g>
      ) : null}
    </svg>
  );
}
