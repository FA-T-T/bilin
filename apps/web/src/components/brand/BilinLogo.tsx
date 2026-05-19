import { useId } from "react";

interface BilinLogoProps {
  className?: string;
  decorative?: boolean;
  title?: string;
  variant?: "main" | "page";
  wordmark?: string;
}

export function BilinLogo({
  className,
  decorative = false,
  title = "Bilin",
  variant = "main",
  wordmark = "Bilin"
}: BilinLogoProps) {
  const rawId = useId().replace(/:/g, "");
  const classNames = ["bilin-logo", className].filter(Boolean).join(" ");

  return (
    <svg
      aria-hidden={decorative || undefined}
      aria-label={decorative ? undefined : title}
      className={classNames}
      data-variant={variant}
      focusable="false"
      height="64"
      role={decorative ? undefined : "img"}
      viewBox={variant === "page" ? "0 0 188 64" : "0 0 64 64"}
      width={variant === "page" ? "188" : "64"}
      xmlns="http://www.w3.org/2000/svg"
    >
      <defs>
        <linearGradient
          id={`${rawId}-field`}
          x1="6"
          x2="58"
          y1="5"
          y2="59"
          gradientUnits="userSpaceOnUse"
        >
          <stop stopColor="var(--bilin-logo-field-a)" />
          <stop offset="0.42" stopColor="var(--bilin-logo-field-b)" />
          <stop offset="1" stopColor="var(--bilin-logo-field-c)" />
        </linearGradient>
        <radialGradient
          id={`${rawId}-aurora`}
          cx="0"
          cy="0"
          r="1"
          gradientTransform="matrix(39 -35 35 39 18 51)"
          gradientUnits="userSpaceOnUse"
        >
          <stop stopColor="var(--bilin-logo-aurora-a)" stopOpacity="0.9" />
          <stop offset="0.52" stopColor="var(--bilin-logo-aurora-b)" stopOpacity="0.5" />
          <stop offset="1" stopColor="var(--bilin-logo-aurora-c)" stopOpacity="0" />
        </radialGradient>
        <linearGradient
          id={`${rawId}-prism`}
          x1="12"
          x2="52"
          y1="50"
          y2="14"
          gradientUnits="userSpaceOnUse"
        >
          <stop stopColor="var(--bilin-logo-prism-a)" />
          <stop offset="0.34" stopColor="var(--bilin-logo-prism-b)" />
          <stop offset="0.67" stopColor="var(--bilin-logo-prism-c)" />
          <stop offset="1" stopColor="var(--bilin-logo-prism-d)" />
        </linearGradient>
        <linearGradient
          id={`${rawId}-page`}
          x1="13"
          x2="52"
          y1="40"
          y2="53"
          gradientUnits="userSpaceOnUse"
        >
          <stop stopColor="var(--bilin-logo-page-a)" />
          <stop offset="0.52" stopColor="var(--bilin-logo-page-b)" />
          <stop offset="1" stopColor="var(--bilin-logo-page-c)" />
        </linearGradient>
        <filter
          id={`${rawId}-glow`}
          x="-18%"
          y="-18%"
          width="136%"
          height="136%"
          colorInterpolationFilters="sRGB"
        >
          <feGaussianBlur in="SourceGraphic" result="blur" stdDeviation="1.4" />
          <feMerge>
            <feMergeNode in="blur" />
            <feMergeNode in="SourceGraphic" />
          </feMerge>
        </filter>
      </defs>

      <g className="bilin-logo__icon">
        <rect className="bilin-logo__cast" x="6" y="7" width="52" height="52" rx="16" />
        <rect
          className="bilin-logo__frame"
          x="4.5"
          y="4.5"
          width="55"
          height="55"
          rx="17"
          fill={`url(#${rawId}-field)`}
        />
        <rect
          className="bilin-logo__aurora"
          x="4.5"
          y="4.5"
          width="55"
          height="55"
          rx="17"
          fill={`url(#${rawId}-aurora)`}
        />

        <g className="bilin-logo__sun" filter={`url(#${rawId}-glow)`}>
          <circle cx="42.2" cy="15.9" r="3.5" />
          <path d="M42.2 8.7v2.3M49.2 15.9h2.3M47.2 10.9l-1.6 1.6M37.2 10.9l1.6 1.6" />
        </g>
        <g className="bilin-logo__moon" filter={`url(#${rawId}-glow)`}>
          <path d="M47.6 11.2c-3.9 1-6.7 4.6-6.7 8.8 0 4 2.6 7.4 6.1 8.6-1.5 0.8-3.1 1.2-5 1.2-5.4 0-9.8-4.4-9.8-9.8s4.4-9.8 9.8-9.8c2.1 0 4 0.4 5.6 1Z" />
          <circle cx="50.9" cy="14.6" r="1.4" />
        </g>

        <path
          className="bilin-logo__page-fill"
          d="M12.7 43.6c6.3-2.3 12.9-1.1 19.2 5.8 6.4-6.9 13.1-8.1 19.4-5.8-0.4-4.7-2.9-8.3-7.2-10.5-4.3-2.2-8.5-1.2-12.2 3.1-3.7-4.3-7.9-5.3-12.2-3.1-4.2 2.2-6.6 5.8-7 10.5Z"
          fill={`url(#${rawId}-page)`}
        />
        <path
          className="bilin-logo__page-ridge"
          d="M12.7 43.6c6.3-2.3 12.9-1.1 19.2 5.8 6.4-6.9 13.1-8.1 19.4-5.8"
          stroke={`url(#${rawId}-prism)`}
        />
        <path
          className="bilin-logo__page-ridge bilin-logo__page-ridge--inner"
          d="M31.9 36.2v13.2"
          stroke={`url(#${rawId}-prism)`}
        />

        <g className="bilin-logo__letter" filter={`url(#${rawId}-glow)`}>
          <path className="bilin-logo__letter-spine" d="M23.8 15.4v35" />
          <path
            className="bilin-logo__letter-loop bilin-logo__letter-loop--upper"
            d="M23.8 16h12.1c7.8 0 12.9 4 12.9 9.6 0 5.7-5.1 9.7-13.1 9.7H23.8"
          />
          <path
            className="bilin-logo__letter-loop bilin-logo__letter-loop--lower"
            d="M23.8 31.5h13.7c8.4 0 13.8 4.3 13.8 10.1 0 6-5.4 9.8-13.9 9.8H23.8"
          />
        </g>
      </g>

      {variant === "page" ? (
        <g className="bilin-logo__wordmark">
          <text className="bilin-logo__wordmark-text" x="76" y="38">
            {wordmark}
          </text>
          <path
            className="bilin-logo__wordmark-line"
            d="M77 47.5c19.5-6.4 43.8-6.4 72.8 0"
            stroke={`url(#${rawId}-prism)`}
          />
        </g>
      ) : null}
    </svg>
  );
}
