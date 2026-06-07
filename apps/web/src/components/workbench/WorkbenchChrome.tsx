import { Button, Card, Divider, Title } from "@mantine/core";
import type { ButtonProps, CardProps, DividerProps, TitleProps } from "@mantine/core";
import type React from "react";

type LegacyButtonVariant = "ghost" | "danger";
type LegacyButtonSize = "small";
type WorkbenchButtonSize = ButtonProps["size"] | LegacyButtonSize;
type WorkbenchButtonVariant = ButtonProps["variant"] | LegacyButtonVariant;

function cx(classNames: Array<string | undefined | null | false>) {
  return classNames.filter(Boolean).join(" ");
}

function resolveButtonVariant(variant: WorkbenchButtonVariant = "filled") {
  if (variant === "ghost") return "light";
  if (variant === "danger") return "filled";
  return variant;
}

function resolveButtonColor(variant: WorkbenchButtonVariant = "filled", color?: ButtonProps["color"]) {
  if (color) return color;
  return variant === "danger" ? "red" : undefined;
}

function resolveButtonSize(size: WorkbenchButtonSize = "sm") {
  return size === "small" ? "sm" : size;
}

type WorkbenchButtonProps = Omit<ButtonProps, "size" | "variant" | "leftSection" | "rightSection"> & {
  size?: WorkbenchButtonSize;
  variant?: WorkbenchButtonVariant;
  icon?: React.ReactNode;
  leftSection?: React.ReactNode;
  rightSection?: React.ReactNode;
  onClick?: React.MouseEventHandler<HTMLButtonElement>;
};

export function WorkbenchButton({
  className,
  color,
  size = "sm",
  variant = "filled",
  icon,
  leftSection,
  rightSection,
  ...props
}: WorkbenchButtonProps) {
  const workbenchSize = resolveButtonSize(size);
  const workbenchVariant = resolveButtonVariant(variant);
  return (
    <Button
      {...props}
      className={cx([className, "workbench-button"])}
      color={resolveButtonColor(variant, color)}
      leftSection={leftSection ?? icon}
      rightSection={rightSection}
      size={workbenchSize}
      variant={workbenchVariant}
    />
  );
}

type WorkbenchCardVariant = "default";

type WorkbenchCardProps = Omit<CardProps, "variant"> & {
  variant?: WorkbenchCardVariant;
};

export function WorkbenchCard({ className, variant = "default", ...props }: WorkbenchCardProps) {
  return (
    <Card
      {...props}
      className={cx(["panel-card", className])}
      padding="lg"
      data-workbench-variant={variant}
    />
  );
}

type WorkbenchDividerProps = DividerProps;

export function WorkbenchDivider({ className, variant = "solid", ...props }: WorkbenchDividerProps) {
  return <Divider {...props} className={cx([className])} variant={variant} />;
}

type WorkbenchTitleProps = {
  className?: string;
  headingLevel?: 1 | 2 | 3 | 4 | 5 | 6;
  name: string;
} & Omit<TitleProps, "order">;

export function WorkbenchTitle({
  className,
  headingLevel = 1,
  name,
  ...props
}: WorkbenchTitleProps) {
  return (
    <Title {...props} className={cx([className])} order={headingLevel}>
      {name}
    </Title>
  );
}
