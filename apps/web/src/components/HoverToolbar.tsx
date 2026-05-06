import { ActionIcon, Group, Tooltip } from "@mantine/core";
import { memo } from "react";
import {
  READER_TOOLBAR_ACTIONS,
  type ReaderToolbarActionId,
  type ToolbarKind
} from "./readerToolbarActions";
import { useT } from "../i18n";

const emptyDisabledActions: ReaderToolbarActionId[] = [];

export const HoverToolbar = memo(function HoverToolbar({
  kind,
  disabledActions = emptyDisabledActions,
  onAction
}: {
  kind: ToolbarKind;
  disabledActions?: ReaderToolbarActionId[];
  onAction?: (actionId: ReaderToolbarActionId) => void;
}) {
  const t = useT();
  return (
    <Group className="hover-toolbar" gap={4}>
      {READER_TOOLBAR_ACTIONS[kind].map((action) => {
        const label = t(action.labelKey);
        return (
          <Tooltip key={action.id} label={label}>
            <ActionIcon
              size="sm"
              variant="default"
              aria-label={label}
              disabled={disabledActions.includes(action.id) || !onAction}
              onClick={(event) => {
                event.stopPropagation();
                onAction?.(action.id);
              }}
            >
              {action.icon}
            </ActionIcon>
          </Tooltip>
        );
      })}
    </Group>
  );
});
