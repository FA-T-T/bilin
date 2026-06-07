import type React from "react";
import {
  Button as ZeldaButton,
  Card as ZeldaCard,
  Divider as ZeldaDivider,
  RupeeCounter,
  SheikahBackground,
  SheikahScanlines,
  TitleQuest
} from "zelda-hyrule-ui";
import type {
  ButtonProps as ZeldaButtonProps,
  CardProps as ZeldaCardProps,
  DividerProps as ZeldaDividerProps,
  RupeeColor
} from "zelda-hyrule-ui";

function cx(...classNames: Array<string | false | null | undefined>) {
  return classNames.filter(Boolean).join(" ");
}

export function HyruleBackdrop({
  children,
  className
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <SheikahBackground color="darkBlue" className={cx("hyrule-backdrop", className)}>
      <SheikahScanlines opacity={0.032} className="hyrule-backdrop-scanlines" />
      <div className="hyrule-backdrop-inner">{children}</div>
    </SheikahBackground>
  );
}

export function HyruleButton({
  className,
  htmlType = "button",
  size = "small",
  variant = "sheikah",
  ...props
}: ZeldaButtonProps) {
  return (
    <ZeldaButton
      {...props}
      className={cx("hyrule-zbutton", className)}
      htmlType={htmlType}
      size={size}
      variant={variant}
    />
  );
}

export function HyruleCard({ className, variant = "sheikah", ...props }: ZeldaCardProps) {
  return <ZeldaCard {...props} className={cx("hyrule-card", className)} variant={variant} />;
}

export function HyruleDivider({ className, variant = "ornament", ...props }: ZeldaDividerProps) {
  return <ZeldaDivider {...props} className={cx("hyrule-divider", className)} variant={variant} />;
}

export function HyruleQuestTitle({
  className,
  headingLevel,
  name,
  questType = "main"
}: {
  className?: string;
  headingLevel?: 1 | 2 | 3 | 4 | 5 | 6;
  name: string;
  questType?: "main" | "side" | "shrine";
}) {
  return (
    <div
      aria-label={headingLevel ? name : undefined}
      aria-level={headingLevel}
      className={cx("hyrule-quest-title-shell", className)}
      role={headingLevel ? "heading" : undefined}
    >
      <span aria-hidden={headingLevel ? true : undefined} className="hyrule-quest-title-visual">
        <TitleQuest className="hyrule-quest-title" name={name} questType={questType} />
      </span>
    </div>
  );
}

export function HyruleRupeeMetric({
  amount,
  color = "green",
  label
}: {
  amount: number;
  color?: RupeeColor;
  label?: string;
}) {
  return (
    <span className="hyrule-rupee-metric" aria-label={label}>
      <RupeeCounter amount={amount} color={color} showLabel />
    </span>
  );
}
