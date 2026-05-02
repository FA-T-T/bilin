import {
  Alert,
  Badge,
  Button,
  Checkbox,
  Collapse,
  Divider,
  Group,
  Loader,
  Modal,
  SegmentedControl,
  Select,
  Stack,
  Tabs,
  Text,
  Textarea,
  TextInput,
  Title
} from "@mantine/core";
import {
  BookMarked,
  ChevronDown,
  ChevronRight,
  Check,
  Download,
  FileText,
  Languages,
  ListTree,
  MessageSquare,
  RefreshCw,
  Search,
  Send,
  X
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";
import { useParams, useSearchParams } from "react-router-dom";

import { API_BASE_URL } from "../api/client";
import {
  useArticleGlossary,
  useArticleChat,
  useArticleDocument,
  useArticleTranslations,
  useAskArticleQuestionStream,
  useCreateNotePatchFromChat,
  useCreateNoteTemplate,
  useCreateGlossaryTerm,
  useExportArticle,
  useExtractGlossary,
  useGenerateNotePatch,
  useNotePatches,
  useNoteTemplates,
  useProviders,
  useRejectNotePatch,
  useSelectTranslationVariant,
  useTranslateArticle,
  useTranslateBlock,
  useUpdateGlossaryTerm,
  useUpdateNotePatch
} from "../api/hooks";
import type {
  ArticleDocument,
  ArticleExportKind,
  ArticleExportResult,
  AssetRecord,
  ChatMessage,
  DocumentBlock,
  ExternalCitation,
  GlossaryTerm,
  NotePatch,
  NotePatchUpdate,
  NoteTemplate,
  RetrievedBlock,
  TranslationVariant
} from "../api/types";
import {
  ReaderBlock,
  type ReaderAssetFile,
  type ReferenceTargets
} from "../components/ReaderBlock";
import { ReaderBlockList } from "../components/ReaderBlockList";
import type { ReaderToolbarActionId } from "../components/readerToolbarActions";
import { activeGlossaryTerms, applyGlossaryToMarkdown } from "../glossary";
import { type ReaderViewMode, useUiStore } from "../state/ui";

export function ReaderPage() {
  const { articleId } = useParams();
  const [searchParams] = useSearchParams();
  const libraryId = searchParams.get("libraryId") ?? undefined;
  const hasArticleContext = Boolean(libraryId && articleId);
  const viewMode = useUiStore((state) => state.readerViewMode);
  const setReaderViewMode = useUiStore((state) => state.setReaderViewMode);
  const providers = useProviders();
  const [targetLanguage, setTargetLanguage] = useState("zh-CN");
  const [selectedProviderId, setSelectedProviderId] = useState<string | null>(null);
  const [chatBlockUid, setChatBlockUid] = useState<string | null>(null);
  const [question, setQuestion] = useState("");
  const [nativeSearch, setNativeSearch] = useState(false);
  const [selectedTemplateId, setSelectedTemplateId] = useState("deep_reading");
  const [exportKind, setExportKind] = useState<ArticleExportKind>("bilingual_markdown");
  const [inspectedBlock, setInspectedBlock] = useState<DocumentBlock | null>(null);
  const [retranslationBlock, setRetranslationBlock] = useState<DocumentBlock | null>(null);
  const [customRetranslationPrompt, setCustomRetranslationPrompt] = useState("");
  const [variantOverrides, setVariantOverrides] = useState<Record<string, string>>({});
  const [streamingAnswer, setStreamingAnswer] = useState("");
  const [streamingCitedBlocks, setStreamingCitedBlocks] = useState<RetrievedBlock[]>([]);
  const [readerActionMessage, setReaderActionMessage] = useState<string | null>(null);
  const [activeBlockUid, setActiveBlockUid] = useState<string | null>(null);
  const [chaptersOpen, setChaptersOpen] = useState(false);
  const document = useArticleDocument(libraryId, articleId);
  const exportArticle = useExportArticle(libraryId, articleId);
  const translations = useArticleTranslations(libraryId, articleId, targetLanguage);
  const glossary = useArticleGlossary(libraryId, articleId, targetLanguage);
  const chat = useArticleChat(libraryId, articleId);
  const noteTemplates = useNoteTemplates(libraryId, articleId);
  const notePatches = useNotePatches(libraryId, articleId);
  const askQuestion = useAskArticleQuestionStream(libraryId, articleId);
  const generateNotePatch = useGenerateNotePatch(libraryId, articleId);
  const createNotePatchFromChat = useCreateNotePatchFromChat(libraryId, articleId);
  const createNoteTemplate = useCreateNoteTemplate(libraryId, articleId);
  const updateNotePatch = useUpdateNotePatch(libraryId, articleId);
  const rejectNotePatch = useRejectNotePatch(libraryId, articleId);
  const extractGlossary = useExtractGlossary(libraryId, articleId);
  const createGlossaryTerm = useCreateGlossaryTerm(libraryId, articleId);
  const updateGlossaryTerm = useUpdateGlossaryTerm(libraryId, articleId);
  const translateArticle = useTranslateArticle(libraryId, articleId);
  const translateBlock = useTranslateBlock(libraryId, articleId);
  const selectTranslationVariant = useSelectTranslationVariant(libraryId, articleId);
  const blocks = useMemo(() => document.data?.blocks ?? [], [document.data?.blocks]);
  const assets = useMemo(() => document.data?.assets ?? [], [document.data?.assets]);
  const title = articleTitle(document.data);
  const subtitle = documentSubtitle(document.data, libraryId, articleId);
  const navBlocks = blocks.filter((block) => block.block_type === "section");
  const activeNavBlockUid = useMemo(
    () => navBlockUidForActiveBlock(blocks, navBlocks, activeBlockUid),
    [activeBlockUid, blocks, navBlocks]
  );
  const referenceTargets = useMemo(() => referenceTargetsForBlocks(blocks), [blocks]);

  const assetById = new Map(assets.map((asset) => [asset.asset_id, asset] as const));
  const variantsByBlockUid = useMemo(() => {
    const map = new Map<string, TranslationVariant[]>();
    for (const variant of translations.data?.variants ?? []) {
      const blockUid = variant.metadata?.block_uid;
      if (typeof blockUid !== "string") continue;
      const variants = map.get(blockUid) ?? [];
      variants.push(variant);
      map.set(blockUid, variants);
    }
    for (const variants of map.values()) {
      variants.sort((left, right) => {
        if (left.is_default !== right.is_default) return left.is_default ? -1 : 1;
        return String(right.updated_at).localeCompare(String(left.updated_at));
      });
    }
    return map;
  }, [translations.data?.variants]);
  const selectedVariantByBlockUid = useMemo(() => {
    const map = new Map<string, TranslationVariant>();
    for (const [blockUid, variants] of variantsByBlockUid.entries()) {
      const override = variants.find((variant) => variant.id === variantOverrides[blockUid]);
      const selected = override ?? variants.find((variant) => variant.is_default) ?? variants[0];
      if (selected) {
        map.set(blockUid, selected);
      }
    }
    return map;
  }, [variantOverrides, variantsByBlockUid]);
  const translationByBlockUid = useMemo(() => {
    const map = new Map<string, string>();
    const terms = activeGlossaryTerms(glossary.data?.terms ?? []);
    for (const [blockUid, variant] of selectedVariantByBlockUid.entries()) {
      map.set(blockUid, applyGlossaryToMarkdown(variant.raw_markdown, terms));
    }
    return map;
  }, [glossary.data?.terms, selectedVariantByBlockUid]);
  const affectedBlockUids = useMemo(
    () => new Set(glossary.data?.affected_block_uids ?? []),
    [glossary.data?.affected_block_uids]
  );
  const selectedProvider = (providers.data ?? []).find(
    (provider) => provider.id === selectedProviderId
  );

  useEffect(() => {
    if (!selectedProviderId && providers.data?.[0]) {
      setSelectedProviderId(providers.data[0].id);
    }
  }, [providers.data, selectedProviderId]);

  useEffect(() => {
    const templates = noteTemplates.data ?? [];
    if (templates.length > 0 && !templates.some((template) => template.id === selectedTemplateId)) {
      setSelectedTemplateId(templates[0].id);
    }
  }, [noteTemplates.data, selectedTemplateId]);

  useEffect(() => {
    setVariantOverrides({});
  }, [articleId, targetLanguage]);

  useEffect(() => {
    if (blocks.length === 0) {
      setActiveBlockUid(null);
      return;
    }
    if (!activeBlockUid || !blocks.some((block) => block.block_uid === activeBlockUid)) {
      setActiveBlockUid(blocks[0].block_uid);
    }
  }, [activeBlockUid, blocks]);

  const translationPayload = {
    target_language: targetLanguage,
    provider_profile_id: selectedProviderId ?? "",
    model: selectedProvider?.default_model ?? null,
    glossary_version: glossary.data?.active_version ?? null,
    force: false,
    block_uids: null,
    custom_prompt: null
  };

  const queueArticleTranslation = () => {
    if (!selectedProviderId) return;
    translateArticle.mutate(translationPayload);
  };

  const queueBlockTranslation = (blockUid: string, customPrompt?: string) => {
    if (!selectedProviderId) return;
    translateBlock.mutate({
      blockUid,
      payload: {
        ...translationPayload,
        force: true,
        block_uids: [blockUid],
        custom_prompt: customPrompt?.trim() || null
      }
    });
  };

  const submitCustomRetranslation = () => {
    if (!retranslationBlock) return;
    queueBlockTranslation(retranslationBlock.block_uid, customRetranslationPrompt);
    setReaderActionMessage(`Queued retranslation for ${retranslationBlock.block_uid}.`);
    setRetranslationBlock(null);
    setCustomRetranslationPrompt("");
  };

  const handleTranslationVariantChange = (blockUid: string, variantId: string) => {
    setVariantOverrides((current) => ({ ...current, [blockUid]: variantId }));
    selectTranslationVariant.mutate({ variantId, targetLanguage });
    setReaderActionMessage(`Selected translation variant for ${blockUid}.`);
  };

  const queueAffectedRetranslation = () => {
    const affected = glossary.data?.affected_block_uids ?? [];
    if (!selectedProviderId || affected.length === 0) return;
    translateArticle.mutate({
      ...translationPayload,
      force: true,
      block_uids: affected
    });
  };

  const submitQuestion = () => {
    if (!selectedProviderId || !question.trim()) return;
    setStreamingAnswer("");
    setStreamingCitedBlocks([]);
    askQuestion.mutate({
      payload: {
        question: question.trim(),
        provider_profile_id: selectedProviderId,
        model: selectedProvider?.default_model ?? null,
        current_block_uid: chatBlockUid,
        max_blocks: 6,
        native_search: nativeSearch,
        retrieval_mode: "auto"
      },
      onMessage: (message) => {
        const data = message.data;
        if (message.event === "evidence" && isEvidenceStreamData(data)) {
          setStreamingCitedBlocks(data.cited_blocks);
        }
        if (message.event === "delta" && isDeltaStreamData(data)) {
          setStreamingAnswer((current) => `${current}${data.text}`);
        }
        if (message.event === "done") {
          setStreamingAnswer("");
          setStreamingCitedBlocks([]);
        }
      }
    });
    setQuestion("");
  };

  const createNotePatchFromMessage = (messageId: string) => {
    createNotePatchFromChat.mutate({
      messageId,
      payload: { title: null }
    });
  };

  const queueNoteGeneration = () => {
    if (!selectedProviderId || !selectedTemplateId) return;
    generateNotePatch.mutate({
      provider_profile_id: selectedProviderId,
      template_id: selectedTemplateId,
      model: selectedProvider?.default_model ?? null,
      max_blocks: 12,
      include_chat_history: true
    });
  };

  const queueExport = () => {
    exportArticle.mutate({
      kind: exportKind,
      target_language: targetLanguage,
      include_untranslated: true
    });
  };

  const copyText = async (text: string, label: string) => {
    if (!text.trim()) {
      setReaderActionMessage(`${label} has no text to copy.`);
      return;
    }
    try {
      if (!navigator.clipboard?.writeText) {
        throw new Error("Clipboard API unavailable");
      }
      await navigator.clipboard.writeText(text);
      setReaderActionMessage(`${label} copied.`);
    } catch {
      setReaderActionMessage("Clipboard is unavailable. Select the text and copy it manually.");
    }
  };

  const handleToolbarAction = (
    actionId: ReaderToolbarActionId,
    block: DocumentBlock,
    content: string
  ) => {
    if (actionId === "copy-source" || actionId === "copy-block") {
      void copyText(block.source_markdown, "Source block");
      return;
    }
    if (actionId === "copy-translation") {
      void copyText(content, "Translation block");
      return;
    }
    if (actionId === "ask-source" || actionId === "explain-block") {
      setChatBlockUid(block.block_uid);
      setReaderActionMessage(`Current block set to ${block.block_uid}.`);
      return;
    }
    if (actionId === "show-latex" || actionId === "show-source") {
      setInspectedBlock(block);
      return;
    }
    if (actionId === "retranslate") {
      if (!selectedProviderId) {
        setReaderActionMessage("Select a provider before retranslating this block.");
        return;
      }
      setRetranslationBlock(block);
      setCustomRetranslationPrompt("");
      return;
    }
    if (actionId === "add-note-patch") {
      setChatBlockUid(block.block_uid);
      setReaderActionMessage(`Block ${block.block_uid} is selected for notes and questions.`);
    }
  };

  return (
    <div className="reader-page">
      <Modal
        opened={Boolean(inspectedBlock)}
        onClose={() => setInspectedBlock(null)}
        title="Source inspector"
        size="lg"
        closeButtonProps={{ "aria-label": "Close source inspector" }}
      >
        {inspectedBlock ? (
          <pre className="source-inspector">
            {inspectedBlock.source_latex || inspectedBlock.source_markdown}
          </pre>
        ) : null}
      </Modal>
      <Modal
        opened={Boolean(retranslationBlock)}
        onClose={() => {
          setRetranslationBlock(null);
          setCustomRetranslationPrompt("");
        }}
        title={
          retranslationBlock
            ? `Retranslate block ${retranslationBlock.block_uid}`
            : "Retranslate block"
        }
        size="lg"
        closeButtonProps={{ "aria-label": "Close retranslation dialog" }}
      >
        <Textarea
          label="Custom prompt"
          placeholder="Optional instruction for this block, for example preserve a term or use a shorter academic style"
          autosize
          minRows={4}
          value={customRetranslationPrompt}
          onChange={(event) => setCustomRetranslationPrompt(event.target.value)}
        />
        <Group justify="flex-end" mt="md">
          <Button
            leftSection={<RefreshCw size={16} />}
            onClick={submitCustomRetranslation}
            loading={translateBlock.isPending}
            disabled={!selectedProviderId || !retranslationBlock}
          >
            Queue retranslation
          </Button>
        </Group>
      </Modal>
      <main className="reader-main">
        <Group justify="space-between" align="flex-start" mb="md">
          <div>
            <Title order={1}>{title}</Title>
            <Text c="dimmed">{subtitle}</Text>
          </div>
          <SegmentedControl
            data-testid="reader-view-mode"
            value={viewMode}
            onChange={(value) => setReaderViewMode(value as ReaderViewMode)}
            data={[
              { label: "Study", value: "study" },
              { label: "Focus", value: "focus" },
              { label: "Bilingual", value: "bilingual" },
              { label: "Translation", value: "translation" },
              { label: "Source", value: "source" }
            ]}
          />
        </Group>
        {navBlocks.length > 0 ? (
          <section className="reader-chapters" aria-label="Parsed chapters">
            <Button
              variant="subtle"
              leftSection={<ListTree size={16} />}
              rightSection={chaptersOpen ? <ChevronDown size={16} /> : <ChevronRight size={16} />}
              onClick={() => setChaptersOpen((open) => !open)}
            >
              Chapters
            </Button>
            <Collapse in={chaptersOpen}>
              <nav className="reader-chapter-list" aria-label="Parsed chapters">
                {navBlocks.map((block, index) => (
                  <a
                    key={block.block_uid}
                    href={`#${block.block_uid}`}
                    className={
                      activeNavBlockUid === block.block_uid ? "reader-nav-active" : undefined
                    }
                    aria-current={activeNavBlockUid === block.block_uid ? "location" : undefined}
                    onMouseEnter={() => setActiveBlockUid(block.block_uid)}
                    onClick={() => setActiveBlockUid(block.block_uid)}
                  >
                    <Badge variant="light" size="sm">
                      {chapterNumber(index, block)}
                    </Badge>
                    <span>{chapterTitle(block)}</span>
                  </a>
                ))}
              </nav>
            </Collapse>
          </section>
        ) : null}
        {readerActionMessage ? (
          <Text c="dimmed" size="sm" mb="md" role="status">
            {readerActionMessage}
          </Text>
        ) : null}
        {hasArticleContext ? (
          <Tabs defaultValue="translate" className="reader-workbench" keepMounted={false}>
            <Tabs.List>
              <Tabs.Tab value="translate" leftSection={<Languages size={15} />}>
                Translate
              </Tabs.Tab>
              <Tabs.Tab value="glossary" leftSection={<BookMarked size={15} />}>
                Terms
              </Tabs.Tab>
              <Tabs.Tab value="chat" leftSection={<MessageSquare size={15} />}>
                Ask
              </Tabs.Tab>
              <Tabs.Tab value="notes" leftSection={<FileText size={15} />}>
                Notes
              </Tabs.Tab>
              <Tabs.Tab value="export" leftSection={<Download size={15} />}>
                Export
              </Tabs.Tab>
            </Tabs.List>

            <Tabs.Panel value="translate">
              <div className="panel reader-translation-panel">
                <Group align="end">
                  <Select
                    label="Provider"
                    placeholder="Configure a provider in Settings"
                    value={selectedProviderId}
                    onChange={setSelectedProviderId}
                    data={(providers.data ?? []).map((provider) => ({
                      label: `${provider.name} · ${provider.default_model ?? "no model"}`,
                      value: provider.id
                    }))}
                  />
                  <TextInput
                    label="Target language"
                    value={targetLanguage}
                    onChange={(event) => setTargetLanguage(event.target.value)}
                  />
                  <Button
                    leftSection={<Languages size={16} />}
                    onClick={queueArticleTranslation}
                    loading={translateArticle.isPending}
                    disabled={!selectedProviderId || !targetLanguage.trim() || blocks.length === 0}
                  >
                    Translate paper
                  </Button>
                </Group>
                <Text c="dimmed" size="sm" mt="sm">
                  Translation jobs target paragraphs and captions. Quality depends on the selected
                  model, language, and domain terminology.
                </Text>
                {translateArticle.data ? (
                  <Text c="dimmed" size="sm" mt="xs">
                    Queued {translateArticle.data.jobs_created} blocks, reused{" "}
                    {translateArticle.data.cached_blocks} cached blocks.
                  </Text>
                ) : null}
                {translateArticle.isError || translateBlock.isError ? (
                  <Text c="red" size="sm" mt="xs">
                    Translation could not be queued. Check provider settings and API availability.
                  </Text>
                ) : null}
              </div>
            </Tabs.Panel>

            <Tabs.Panel value="glossary">
              <GlossaryPanel
                terms={glossary.data?.terms ?? []}
                targetLanguage={targetLanguage}
                activeVersion={glossary.data?.active_version ?? "glossary:none"}
                affectedBlockUids={glossary.data?.affected_block_uids ?? []}
                isLoading={glossary.isLoading}
                isExtracting={extractGlossary.isPending}
                isSaving={createGlossaryTerm.isPending || updateGlossaryTerm.isPending}
                canRetranslate={Boolean(selectedProviderId)}
                onExtract={() =>
                  extractGlossary.mutate({
                    target_language: targetLanguage,
                    limit: 40
                  })
                }
                onCreate={(sourceTerm, targetTerm) =>
                  createGlossaryTerm.mutate({
                    source_term: sourceTerm,
                    target_term: targetTerm,
                    language_direction: `en->${targetLanguage}`,
                    status: "active",
                    metadata: { target_language: targetLanguage }
                  })
                }
                onConfirm={(term, targetTerm) =>
                  updateGlossaryTerm.mutate({
                    termId: term.id,
                    payload: {
                      target_term: targetTerm,
                      status: "active",
                      metadata: { target_language: targetLanguage }
                    }
                  })
                }
                onRetranslateAffected={queueAffectedRetranslation}
              />
            </Tabs.Panel>

            <Tabs.Panel value="chat">
              <ChatPanel
                messages={chat.data?.messages ?? []}
                citedBlocks={
                  streamingCitedBlocks.length > 0
                    ? streamingCitedBlocks
                    : (askQuestion.data?.cited_blocks ?? [])
                }
                streamingAnswer={streamingAnswer}
                selectedBlockUid={chatBlockUid}
                question={question}
                nativeSearch={nativeSearch}
                nativeSearchAvailable={Boolean(selectedProvider?.capabilities?.native_search)}
                isAsking={askQuestion.isPending}
                isCreatingNotePatch={createNotePatchFromChat.isPending}
                canAsk={Boolean(selectedProviderId)}
                canCreateNotePatch={Boolean(selectedProviderId)}
                error={askQuestion.isError}
                onQuestionChange={setQuestion}
                onNativeSearchChange={setNativeSearch}
                onClearBlock={() => setChatBlockUid(null)}
                onAsk={submitQuestion}
                onCreateNotePatch={createNotePatchFromMessage}
              />
            </Tabs.Panel>

            <Tabs.Panel value="notes">
              <NotesPanel
                templates={noteTemplates.data ?? []}
                patches={notePatches.data?.patches ?? []}
                selectedTemplateId={selectedTemplateId}
                isLoading={noteTemplates.isLoading || notePatches.isLoading}
                isGenerating={generateNotePatch.isPending}
                isSavingPatch={updateNotePatch.isPending}
                isSavingTemplate={createNoteTemplate.isPending}
                isRejecting={rejectNotePatch.isPending}
                canGenerate={Boolean(selectedProviderId && blocks.length > 0)}
                error={
                  generateNotePatch.isError ||
                  createNoteTemplate.isError ||
                  updateNotePatch.isError ||
                  rejectNotePatch.isError
                }
                onTemplateChange={setSelectedTemplateId}
                onGenerate={queueNoteGeneration}
                onCreateTemplate={(name, description) =>
                  createNoteTemplate.mutate(
                    { name, description, metadata: { source: "reader" } },
                    { onSuccess: (template) => setSelectedTemplateId(template.id) }
                  )
                }
                onSavePatch={(patchId, payload) => updateNotePatch.mutate({ patchId, payload })}
                onAcceptEdited={(patchId, payload) =>
                  updateNotePatch.mutate({
                    patchId,
                    payload: {
                      ...payload,
                      status: "accepted"
                    }
                  })
                }
                onReject={(patchId) => rejectNotePatch.mutate(patchId)}
              />
            </Tabs.Panel>

            <Tabs.Panel value="export">
              <ExportPanel
                exportKind={exportKind}
                targetLanguage={targetLanguage}
                result={exportArticle.data}
                isExporting={exportArticle.isPending}
                error={exportArticle.isError}
                downloadUrl={exportDownloadUrl(libraryId, articleId, exportArticle.data)}
                onExportKindChange={setExportKind}
                onExport={queueExport}
              />
            </Tabs.Panel>
          </Tabs>
        ) : null}
        {!hasArticleContext ? (
          <Alert color="yellow" mb="md">
            Open an article from a library so the reader can load its parsed document.
          </Alert>
        ) : null}
        {hasArticleContext && document.isLoading ? (
          <Group>
            <Loader size="sm" />
            <Text c="dimmed">Loading article document...</Text>
          </Group>
        ) : null}
        {hasArticleContext && document.isError ? (
          <Alert color="red" mb="md">
            Article document could not be loaded. The import may still be queued, or parsing may
            have failed.
          </Alert>
        ) : null}
        <ReaderBlockList
          blocks={blocks}
          activeBlockUid={activeBlockUid}
          onActiveBlockChange={setActiveBlockUid}
          renderBlock={(block) => {
            const asset = assetForBlock(block, assetById);
            return (
              <ReaderBlock
                key={block.block_uid}
                block={block}
                asset={asset}
                assetUrl={assetUrl(libraryId, articleId, asset)}
                assetFileUrls={assetFileUrls(libraryId, articleId, asset)}
                referenceTargets={referenceTargets}
                translation={translationByBlockUid.get(block.block_uid)}
                translationVariantOptions={translationVariantOptions(
                  variantsByBlockUid.get(block.block_uid) ?? []
                )}
                selectedTranslationVariantId={selectedVariantByBlockUid.get(block.block_uid)?.id}
                glossaryAffected={affectedBlockUids.has(block.block_uid)}
                viewMode={viewMode}
                active={activeBlockUid === block.block_uid}
                onActivate={setActiveBlockUid}
                onTranslationVariantChange={handleTranslationVariantChange}
                onToolbarAction={handleToolbarAction}
              />
            );
          }}
        />
      </main>
    </div>
  );
}

interface GlossaryPanelProps {
  terms: GlossaryTerm[];
  targetLanguage: string;
  activeVersion: string;
  affectedBlockUids: string[];
  isLoading: boolean;
  isExtracting: boolean;
  isSaving: boolean;
  canRetranslate: boolean;
  onExtract: () => void;
  onCreate: (sourceTerm: string, targetTerm: string) => void;
  onConfirm: (term: GlossaryTerm, targetTerm: string) => void;
  onRetranslateAffected: () => void;
}

interface ChatPanelProps {
  messages: ChatMessage[];
  citedBlocks: RetrievedBlock[];
  streamingAnswer: string;
  selectedBlockUid: string | null;
  question: string;
  nativeSearch: boolean;
  nativeSearchAvailable: boolean;
  isAsking: boolean;
  isCreatingNotePatch: boolean;
  canAsk: boolean;
  canCreateNotePatch: boolean;
  error: boolean;
  onQuestionChange: (value: string) => void;
  onNativeSearchChange: (value: boolean) => void;
  onClearBlock: () => void;
  onAsk: () => void;
  onCreateNotePatch: (messageId: string) => void;
}

interface NotesPanelProps {
  templates: NoteTemplate[];
  patches: NotePatch[];
  selectedTemplateId: string;
  isLoading: boolean;
  isGenerating: boolean;
  isSavingPatch: boolean;
  isSavingTemplate: boolean;
  isRejecting: boolean;
  canGenerate: boolean;
  error: boolean;
  onTemplateChange: (value: string) => void;
  onGenerate: () => void;
  onCreateTemplate: (name: string, description: string) => void;
  onSavePatch: (patchId: string, payload: NotePatchUpdate) => void;
  onAcceptEdited: (patchId: string, payload: NotePatchUpdate) => void;
  onReject: (patchId: string) => void;
}

interface ExportPanelProps {
  exportKind: ArticleExportKind;
  targetLanguage: string;
  result?: ArticleExportResult;
  isExporting: boolean;
  error: boolean;
  downloadUrl?: string;
  onExportKindChange: (value: ArticleExportKind) => void;
  onExport: () => void;
}

function ChatPanel({
  messages,
  citedBlocks,
  streamingAnswer,
  selectedBlockUid,
  question,
  nativeSearch,
  nativeSearchAvailable,
  isAsking,
  isCreatingNotePatch,
  canAsk,
  canCreateNotePatch,
  error,
  onQuestionChange,
  onNativeSearchChange,
  onClearBlock,
  onAsk,
  onCreateNotePatch
}: ChatPanelProps) {
  return (
    <div className="panel reader-chat-panel">
      <Group justify="space-between" align="flex-start">
        <div>
          <Group gap="xs">
            <MessageSquare size={18} />
            <Title order={3}>Paper chat</Title>
          </Group>
          <Text c="dimmed" size="sm">
            Answers are grounded in local article blocks and saved with cited block IDs.
          </Text>
        </div>
        {selectedBlockUid ? (
          <Button variant="subtle" size="xs" onClick={onClearBlock}>
            Current block {selectedBlockUid}
          </Button>
        ) : null}
      </Group>
      <Stack gap="sm" mt="md">
        {messages.length === 0 ? (
          <Text c="dimmed" size="sm">
            No questions yet. Use a block toolbar or ask about the whole paper.
          </Text>
        ) : null}
        {messages.map((message) => {
          const sourceRefs = message.source_refs ?? [];
          const externalRefs = message.external_refs ?? [];
          return (
            <div className={`chat-message chat-message-${message.role}`} key={message.id}>
              <Group justify="space-between" align="center">
                <Badge variant="light">{message.role}</Badge>
                {message.role === "assistant" ? (
                  <Button
                    size="xs"
                    variant="subtle"
                    leftSection={<FileText size={14} />}
                    loading={isCreatingNotePatch}
                    disabled={!canCreateNotePatch}
                    onClick={() => onCreateNotePatch(message.id)}
                  >
                    Create note patch
                  </Button>
                ) : null}
              </Group>
              <Text>{message.content}</Text>
              {sourceRefs.length > 0 ? (
                <Group gap="xs" aria-label="Current-paper evidence">
                  {sourceRefs.map((ref) => (
                    <a className="source-ref" href={`#${ref}`} key={ref}>
                      {ref}
                    </a>
                  ))}
                </Group>
              ) : null}
              {externalRefs.length > 0 ? <ExternalEvidence refs={externalRefs} /> : null}
            </div>
          );
        })}
        {streamingAnswer ? (
          <div className="chat-message chat-message-assistant" aria-live="polite">
            <Badge variant="light">assistant</Badge>
            <Text>{streamingAnswer}</Text>
          </div>
        ) : null}
      </Stack>
      {citedBlocks.length > 0 ? (
        <div className="retrieved-blocks">
          <Text fw={600} size="sm">
            Current-paper evidence
          </Text>
          <Group gap="xs" mt="xs">
            {citedBlocks.map((block) => (
              <a className="source-ref" href={`#${block.block_uid}`} key={block.block_uid}>
                {block.block_uid}
              </a>
            ))}
          </Group>
        </div>
      ) : null}
      <Textarea
        label="Question"
        placeholder="Ask about the current paragraph or the whole paper"
        autosize
        minRows={2}
        mt="md"
        value={question}
        onChange={(event) => onQuestionChange(event.target.value)}
      />
      <Group justify="space-between" align="center" mt="sm">
        <Checkbox
          label="Use model-native search"
          checked={nativeSearch}
          disabled={!nativeSearchAvailable}
          onChange={(event) => onNativeSearchChange(event.currentTarget.checked)}
        />
        <Button
          leftSection={<Send size={16} />}
          onClick={onAsk}
          loading={isAsking}
          disabled={!canAsk || !question.trim()}
        >
          Ask paper
        </Button>
      </Group>
      {!nativeSearchAvailable ? (
        <Text c="dimmed" size="xs" mt="xs">
          Native search is disabled for this provider, so answers are restricted to article context.
        </Text>
      ) : null}
      {error ? (
        <Text c="red" size="sm" mt="xs">
          Question could not be answered. Check provider settings or select a parsed article.
        </Text>
      ) : null}
    </div>
  );
}

function ExternalEvidence({ refs }: { refs: ExternalCitation[] }) {
  return (
    <div className="external-evidence">
      <Text fw={600} size="xs">
        External evidence
      </Text>
      <Stack gap={4} mt={4}>
        {refs.map((ref, index) => {
          const label = ref.title || ref.url || ref.doi || ref.arxiv_id || "External citation";
          return (
            <Text size="xs" c="dimmed" key={`${label}-${index}`}>
              {ref.url ? (
                <a href={ref.url} target="_blank" rel="noreferrer">
                  {label}
                </a>
              ) : (
                label
              )}
              {ref.doi ? ` · DOI ${ref.doi}` : ""}
              {ref.arxiv_id ? ` · arXiv ${ref.arxiv_id}` : ""}
            </Text>
          );
        })}
      </Stack>
    </div>
  );
}

function ExportPanel({
  exportKind,
  targetLanguage,
  result,
  isExporting,
  error,
  downloadUrl,
  onExportKindChange,
  onExport
}: ExportPanelProps) {
  const missingTranslationBlockUids = result?.missing_translation_block_uids ?? [];
  return (
    <div className="panel reader-export-panel">
      <Group justify="space-between" align="flex-start">
        <div>
          <Group gap="xs">
            <Download size={18} />
            <Title order={3}>Export</Title>
          </Group>
          <Text c="dimmed" size="sm">
            Write readable Markdown artifacts or a portable bundle zip into the article bundle.
          </Text>
        </div>
        <Group align="end">
          <Select
            label="Export kind"
            value={exportKind}
            data={[
              { value: "bilingual_markdown", label: `Bilingual Markdown (${targetLanguage})` },
              { value: "translated_markdown", label: `Translated Markdown (${targetLanguage})` },
              { value: "source_markdown", label: "Source Markdown" },
              { value: "lecture_notes", label: "Lecture notes" },
              { value: "bundle_zip", label: "Article bundle zip" }
            ]}
            onChange={(value) => {
              if (value) onExportKindChange(value as ArticleExportKind);
            }}
          />
          <Button leftSection={<Download size={16} />} onClick={onExport} loading={isExporting}>
            Export artifact
          </Button>
        </Group>
      </Group>
      {result ? (
        <div className="export-result">
          <Text size="sm">
            Wrote {result.file_name} ({result.bytes_written} bytes).
          </Text>
          {missingTranslationBlockUids.length > 0 ? (
            <Text c="yellow" size="sm">
              Missing translations: {missingTranslationBlockUids.join(", ")}
            </Text>
          ) : null}
          {downloadUrl ? (
            <Button
              component="a"
              href={downloadUrl}
              target="_blank"
              rel="noreferrer"
              variant="light"
              size="xs"
              leftSection={<Download size={14} />}
            >
              Open export
            </Button>
          ) : null}
        </div>
      ) : null}
      {error ? (
        <Text c="red" size="sm" mt="xs">
          Export failed. Check that the article has parsed document artifacts.
        </Text>
      ) : null}
    </div>
  );
}

function NotesPanel({
  templates,
  patches,
  selectedTemplateId,
  isLoading,
  isGenerating,
  isSavingPatch,
  isSavingTemplate,
  isRejecting,
  canGenerate,
  error,
  onTemplateChange,
  onGenerate,
  onCreateTemplate,
  onSavePatch,
  onAcceptEdited,
  onReject
}: NotesPanelProps) {
  const [templateName, setTemplateName] = useState("");
  const [templateDescription, setTemplateDescription] = useState("");
  const [patchDrafts, setPatchDrafts] = useState<Record<string, NotePatchDraft>>({});
  const templateOptions =
    templates.length > 0
      ? templates.map((template) => ({
          value: template.id,
          label: template.custom ? `${template.name} · custom` : template.name
        }))
      : [{ value: "deep_reading", label: "精读模板" }];

  useEffect(() => {
    setPatchDrafts((current) => {
      const next: Record<string, NotePatchDraft> = {};
      let changed = false;
      for (const patch of patches) {
        const draft = current[patch.id];
        next[patch.id] = draft ?? {
          title: patch.title,
          patchMarkdown: patch.patch_markdown
        };
        if (!draft) changed = true;
      }
      if (Object.keys(current).length !== patches.length) changed = true;
      return changed ? next : current;
    });
  }, [patches]);

  const updatePatchDraft = (patchId: string, values: Partial<NotePatchDraft>) => {
    setPatchDrafts((current) => ({
      ...current,
      [patchId]: {
        title: current[patchId]?.title ?? "",
        patchMarkdown: current[patchId]?.patchMarkdown ?? "",
        ...values
      }
    }));
  };

  const submitTemplate = () => {
    const name = templateName.trim();
    const description = templateDescription.trim();
    if (!name || !description) return;
    onCreateTemplate(name, description);
    setTemplateName("");
    setTemplateDescription("");
  };

  return (
    <div className="panel reader-notes-panel">
      <Group justify="space-between" align="flex-start">
        <div>
          <Group gap="xs">
            <FileText size={18} />
            <Title order={3}>Lecture notes</Title>
          </Group>
          <Text c="dimmed" size="sm">
            Generate editable learning-note patches from article evidence and saved chat.
          </Text>
        </div>
        <Group align="end">
          <Select
            label="Template"
            value={selectedTemplateId}
            data={templateOptions}
            onChange={(value) => {
              if (value) onTemplateChange(value);
            }}
          />
          <Button
            leftSection={<FileText size={16} />}
            onClick={onGenerate}
            loading={isGenerating}
            disabled={!canGenerate || !selectedTemplateId}
          >
            Generate patch
          </Button>
        </Group>
      </Group>
      <Stack gap="xs" mt="md">
        <Group align="end">
          <TextInput
            label="Custom template name"
            placeholder="Seminar critique"
            value={templateName}
            onChange={(event) => setTemplateName(event.currentTarget.value)}
          />
          <Textarea
            label="Custom template prompt"
            placeholder="Focus on assumptions, open questions, and discussion points"
            autosize
            minRows={2}
            value={templateDescription}
            onChange={(event) => setTemplateDescription(event.currentTarget.value)}
          />
          <Button
            variant="light"
            onClick={submitTemplate}
            loading={isSavingTemplate}
            disabled={!templateName.trim() || !templateDescription.trim()}
          >
            Save template
          </Button>
        </Group>
      </Stack>
      {isLoading ? (
        <Group mt="sm">
          <Loader size="sm" />
          <Text c="dimmed" size="sm">
            Loading note patches...
          </Text>
        </Group>
      ) : null}
      {error ? (
        <Text c="red" size="sm" mt="xs">
          Note patch action failed. Check provider settings and the article document.
        </Text>
      ) : null}
      <Stack gap="sm" mt="md">
        {patches.length === 0 ? (
          <Text c="dimmed" size="sm">
            No lecture-note patches yet. Generate one from the selected template.
          </Text>
        ) : null}
        {patches.map((patch) => {
          const sourceRefs = patch.source_refs ?? [];
          const draft = patchDrafts[patch.id] ?? {
            title: patch.title,
            patchMarkdown: patch.patch_markdown
          };
          return (
            <div className="note-patch" key={patch.id}>
              <Group justify="space-between" align="flex-start">
                <div>
                  <Group gap="xs">
                    <Badge variant="light" color={noteStatusColor(patch.status)}>
                      {patch.status}
                    </Badge>
                    <Text fw={700}>{patch.title}</Text>
                  </Group>
                  {sourceRefs.length > 0 ? (
                    <Group gap="xs" mt="xs">
                      {sourceRefs.map((ref) => (
                        <a className="source-ref" href={`#${ref}`} key={ref}>
                          {ref}
                        </a>
                      ))}
                    </Group>
                  ) : null}
                </div>
                {patch.status === "proposed" ? (
                  <Group gap="xs">
                    <Button
                      size="xs"
                      variant="light"
                      onClick={() =>
                        onSavePatch(patch.id, {
                          title: draft.title,
                          patch_markdown: draft.patchMarkdown
                        })
                      }
                      loading={isSavingPatch}
                    >
                      Save draft
                    </Button>
                    <Button
                      size="xs"
                      variant="light"
                      color="green"
                      leftSection={<Check size={14} />}
                      loading={isSavingPatch}
                      onClick={() =>
                        onAcceptEdited(patch.id, {
                          title: draft.title,
                          patch_markdown: draft.patchMarkdown
                        })
                      }
                    >
                      Accept edited
                    </Button>
                    <Button
                      size="xs"
                      variant="subtle"
                      color="red"
                      leftSection={<X size={14} />}
                      loading={isRejecting}
                      onClick={() => onReject(patch.id)}
                    >
                      Reject
                    </Button>
                  </Group>
                ) : null}
              </Group>
              {patch.status === "proposed" ? (
                <Stack gap="xs" mt="sm">
                  <TextInput
                    label={`Note title for ${patch.id}`}
                    value={draft.title}
                    onChange={(event) =>
                      updatePatchDraft(patch.id, { title: event.currentTarget.value })
                    }
                  />
                  <Textarea
                    label={`Patch markdown for ${patch.id}`}
                    autosize
                    minRows={5}
                    value={draft.patchMarkdown}
                    onChange={(event) =>
                      updatePatchDraft(patch.id, { patchMarkdown: event.currentTarget.value })
                    }
                  />
                </Stack>
              ) : (
                <pre className="note-markdown">{patch.patch_markdown}</pre>
              )}
            </div>
          );
        })}
      </Stack>
    </div>
  );
}

interface NotePatchDraft {
  title: string;
  patchMarkdown: string;
}

function GlossaryPanel({
  terms,
  targetLanguage,
  activeVersion,
  affectedBlockUids,
  isLoading,
  isExtracting,
  isSaving,
  canRetranslate,
  onExtract,
  onCreate,
  onConfirm,
  onRetranslateAffected
}: GlossaryPanelProps) {
  const [sourceTerm, setSourceTerm] = useState("");
  const [targetTerm, setTargetTerm] = useState("");
  const [candidateTargets, setCandidateTargets] = useState<Record<string, string>>({});
  const activeTerms = terms.filter((term) => term.status === "active");
  const candidates = terms.filter((term) => term.status === "candidate");

  const submitNewTerm = () => {
    const source = sourceTerm.trim();
    const target = targetTerm.trim();
    if (!source || !target) return;
    onCreate(source, target);
    setSourceTerm("");
    setTargetTerm("");
  };

  const confirmCandidate = (term: GlossaryTerm) => {
    const target = (candidateTargets[term.id] ?? term.target_term).trim();
    if (!target) return;
    onConfirm(term, target);
  };

  return (
    <div className="panel reader-glossary-panel">
      <Group justify="space-between" align="flex-start">
        <div>
          <Group gap="xs">
            <BookMarked size={18} />
            <Title order={3}>Glossary</Title>
          </Group>
          <Text c="dimmed" size="sm">
            Article terminology for {targetLanguage}. Active version {activeVersion}.
          </Text>
        </div>
        <Group>
          <Button
            variant="light"
            leftSection={<Search size={16} />}
            onClick={onExtract}
            loading={isExtracting}
          >
            Extract terms
          </Button>
          <Button
            variant="light"
            color="yellow"
            leftSection={<RefreshCw size={16} />}
            disabled={!canRetranslate || affectedBlockUids.length === 0}
            onClick={onRetranslateAffected}
          >
            Retranslate affected
          </Button>
        </Group>
      </Group>
      {isLoading ? (
        <Group mt="sm">
          <Loader size="sm" />
          <Text c="dimmed" size="sm">
            Loading glossary...
          </Text>
        </Group>
      ) : null}
      {affectedBlockUids.length > 0 ? (
        <Alert color="yellow" mt="sm">
          {affectedBlockUids.length} translated blocks were generated with an older glossary
          version.
        </Alert>
      ) : null}
      <Group align="end" mt="md">
        <TextInput
          label="Source term"
          value={sourceTerm}
          onChange={(event) => setSourceTerm(event.target.value)}
        />
        <TextInput
          label="Target term"
          value={targetTerm}
          onChange={(event) => setTargetTerm(event.target.value)}
        />
        <Button
          leftSection={<Check size={16} />}
          onClick={submitNewTerm}
          loading={isSaving}
          disabled={!sourceTerm.trim() || !targetTerm.trim()}
        >
          Add term
        </Button>
      </Group>
      <Divider my="md" />
      <Stack gap="sm">
        {activeTerms.length === 0 && candidates.length === 0 ? (
          <Text c="dimmed" size="sm">
            No glossary terms yet. Extract candidates from the parsed article or add a term
            manually.
          </Text>
        ) : null}
        {activeTerms.map((term) => (
          <div className="glossary-row" key={term.id}>
            <Badge variant="light" color="green">
              Active
            </Badge>
            <Text fw={600}>{term.source_term}</Text>
            <Text c="dimmed">
              {"=>"} {term.target_term}
            </Text>
          </div>
        ))}
        {candidates.map((term) => (
          <div className="glossary-candidate" key={term.id}>
            <div>
              <Group gap="xs">
                <Badge variant="light" color="gray">
                  Candidate
                </Badge>
                <Text fw={600}>{term.source_term}</Text>
              </Group>
              <Text c="dimmed" size="xs">
                {candidateSummary(term)}
              </Text>
            </div>
            <TextInput
              aria-label={`Target term for ${term.source_term}`}
              placeholder="Confirmed target term"
              value={candidateTargets[term.id] ?? term.target_term}
              onChange={(event) =>
                setCandidateTargets((current) => ({
                  ...current,
                  [term.id]: event.target.value
                }))
              }
            />
            <Button
              variant="light"
              leftSection={<Check size={16} />}
              onClick={() => confirmCandidate(term)}
              loading={isSaving}
              disabled={!(candidateTargets[term.id] ?? term.target_term).trim()}
            >
              Confirm
            </Button>
          </div>
        ))}
      </Stack>
    </div>
  );
}

function noteStatusColor(status: string): string {
  if (status === "accepted") return "green";
  if (status === "rejected") return "red";
  return "blue";
}

function candidateSummary(term: GlossaryTerm): string {
  const count = term.metadata?.occurrence_count;
  const blockUids = term.metadata?.block_uids;
  const occurrenceText = typeof count === "number" ? `${count} occurrences` : "rule candidate";
  const blockText = Array.isArray(blockUids) ? ` · ${blockUids.length} blocks` : "";
  return `${occurrenceText}${blockText}`;
}

function translationVariantOptions(variants: TranslationVariant[]) {
  return variants.map((variant, index) => {
    const source =
      variant.metadata?.cache_source === "translation_memory"
        ? "memory"
        : (variant.model ?? "local");
    const status = variant.validation_status === "ok" ? "ok" : variant.validation_status;
    const prefix = variant.is_default ? "Default" : `Variant ${index + 1}`;
    return {
      value: variant.id,
      label: `${prefix} · ${source} · ${status}`
    };
  });
}

function isEvidenceStreamData(data: unknown): data is { cited_blocks: RetrievedBlock[] } {
  return (
    typeof data === "object" &&
    data !== null &&
    Array.isArray((data as { cited_blocks?: unknown }).cited_blocks)
  );
}

function isDeltaStreamData(data: unknown): data is { text: string } {
  return (
    typeof data === "object" &&
    data !== null &&
    typeof (data as { text?: unknown }).text === "string"
  );
}

function articleTitle(document?: ArticleDocument): string {
  const title = document?.manifest.arxiv_metadata?.title;
  return typeof title === "string" && title.trim() ? title : "Article reader";
}

function documentSubtitle(
  document: ArticleDocument | undefined,
  libraryId: string | undefined,
  articleId: string | undefined
): string {
  if (!document) return libraryId ? `Article revision ${articleId}` : "Missing library context.";
  const arxivId = document.manifest.arxiv_id ?? "local article";
  return `${arxivId} · ${document.article_revision.status} · ${document.blocks.length} blocks`;
}

function chapterNumber(index: number, block: DocumentBlock): string {
  const level = block.metadata?.level;
  if (typeof level === "number" && level > 1) return `§${index + 1}`;
  return `${index + 1}`;
}

function chapterTitle(block: DocumentBlock): string {
  const text = block.source_markdown
    .replace(/^#+\s*/, "")
    .replace(/\*\*/g, "")
    .replace(/`/g, "")
    .trim();
  return text || block.structural_path;
}

function assetForBlock(
  block: DocumentBlock,
  assets: Map<string, AssetRecord>
): AssetRecord | undefined {
  const assetId = block.metadata?.asset_id;
  return typeof assetId === "string" ? assets.get(assetId) : undefined;
}

function referenceTargetsForBlocks(blocks: DocumentBlock[]): ReferenceTargets {
  const targets: ReferenceTargets = {};
  for (const block of blocks) {
    const target = { blockUid: block.block_uid, blockType: referenceTargetBlockType(block) };
    targets[block.block_uid] = target;
    const label = block.metadata?.label;
    if (typeof label === "string" && label.trim()) {
      targets[label] = target;
    }
  }
  return targets;
}

function referenceTargetBlockType(block: DocumentBlock): string {
  const label = block.metadata?.label;
  if (
    block.block_type === "figure" &&
    ((typeof label === "string" && /(^tab:|\.T\d+$)/i.test(label)) ||
      /^\*\*Table\s+\d+/i.test(block.source_markdown))
  ) {
    return "table";
  }
  return block.block_type;
}

function navBlockUidForActiveBlock(
  blocks: DocumentBlock[],
  navBlocks: DocumentBlock[],
  activeBlockUid: string | null
): string | null {
  if (!activeBlockUid) return null;
  if (navBlocks.some((block) => block.block_uid === activeBlockUid)) return activeBlockUid;
  const activeIndex = blocks.findIndex((block) => block.block_uid === activeBlockUid);
  for (let index = activeIndex; index >= 0; index -= 1) {
    if (blocks[index]?.block_type === "section") return blocks[index].block_uid;
  }
  return navBlocks[0]?.block_uid ?? activeBlockUid;
}

function assetUrl(
  libraryId: string | undefined,
  articleId: string | undefined,
  asset: AssetRecord | undefined
): string | undefined {
  if (!libraryId || !articleId || !asset?.web_path) return undefined;
  const encodedLibrary = encodeURIComponent(libraryId);
  const encodedArticle = encodeURIComponent(articleId);
  const encodedAsset = encodeURIComponent(asset.asset_id);
  return `${API_BASE_URL}/libraries/${encodedLibrary}/articles/${encodedArticle}/assets/${encodedAsset}`;
}

function assetFileUrls(
  libraryId: string | undefined,
  articleId: string | undefined,
  asset: AssetRecord | undefined
): ReaderAssetFile[] {
  if (!libraryId || !articleId || !asset) return [];
  const assetFiles = asset.metadata?.asset_files;
  if (!Array.isArray(assetFiles)) {
    const originalReference = asset.metadata?.original_reference;
    const url = assetUrl(libraryId, articleId, asset);
    return typeof originalReference === "string" && url
      ? [{ index: 1, originalReference, url }]
      : [];
  }
  const encodedLibrary = encodeURIComponent(libraryId);
  const encodedArticle = encodeURIComponent(articleId);
  const encodedAsset = encodeURIComponent(asset.asset_id);
  return assetFiles.flatMap((item) => {
    if (!item || typeof item !== "object") return [];
    const index = "index" in item ? item.index : undefined;
    const originalReference = "original_reference" in item ? item.original_reference : undefined;
    const webPath = "web_path" in item ? item.web_path : undefined;
    if (
      typeof index !== "number" ||
      typeof originalReference !== "string" ||
      typeof webPath !== "string"
    ) {
      return [];
    }
    return [
      {
        index,
        originalReference,
        url: `${API_BASE_URL}/libraries/${encodedLibrary}/articles/${encodedArticle}/assets/${encodedAsset}/files/${index}`
      }
    ];
  });
}

function exportDownloadUrl(
  libraryId: string | undefined,
  articleId: string | undefined,
  result: ArticleExportResult | undefined
): string | undefined {
  if (!libraryId || !articleId || !result) return undefined;
  const encodedLibrary = encodeURIComponent(libraryId);
  const encodedArticle = encodeURIComponent(articleId);
  const encodedFile = encodeURIComponent(result.file_name);
  return `${API_BASE_URL}/libraries/${encodedLibrary}/articles/${encodedArticle}/exports/${encodedFile}`;
}
