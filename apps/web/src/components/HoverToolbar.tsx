import { ActionIcon, Group, Tooltip } from "@mantine/core";
import {
  READER_TOOLBAR_ACTIONS,
  type ReaderToolbarActionId,
  type ToolbarKind
} from "./readerToolbarActions";

export function HoverToolbar({
  kind,
  disabledActions = [],
  onAction
}: {
  kind: ToolbarKind;
  disabledActions?: ReaderToolbarActionId[];
  onAction?: (actionId: ReaderToolbarActionId) => void;
}) {
  return (
    <Group className="hover-toolbar" gap={4}>
      {READER_TOOLBAR_ACTIONS[kind].map((action) => (
        <Tooltip key={action.id} label={action.label}>
          <ActionIcon
            size="sm"
            variant="default"
            aria-label={action.label}
            disabled={disabledActions.includes(action.id) || !onAction}
            onClick={() => onAction?.(action.id)}
          >
            {action.icon}
          </ActionIcon>
        </Tooltip>
      ))}
    </Group>
  );
}
