# macOS Zotero Integration

Bilin's macOS app should treat Zotero as an external metadata source, not as a database
to mutate. Zotero's own documentation allows direct SQLite access for getting data out,
but warns that the database is internal, should be accessed read-only, and can change
between Zotero releases.

## Product Boundary

- Users can configure a Zotero data directory or a direct `zotero.sqlite` path.
- Bilin reads Zotero items, collections, tags, creators, attachments, and local metadata.
- Bilin extracts arXiv identifiers from Zotero fields such as `Extra` and URL.
- Bilin does not write to Zotero SQLite.
- Bilin does not automatically download remote metadata.
- Bilin does not automatically import a Zotero item into the Bilin library.
- Bilin does not automatically translate Zotero items.

The user action model is explicit:

1. Inspect local Zotero metadata.
2. Choose whether to download arXiv metadata.
3. Choose whether to import the paper into a Bilin library.
4. Choose whether to generate translation after import.

## SQLite Read Surface

The first read-only adapter uses these Zotero tables:

- `items`, `itemTypes`
- `itemData`, `itemDataValues`, `fields`
- `collections`, `collectionItems`
- `tags`, `itemTags`
- `creators`, `itemCreators`, `creatorTypes`
- `itemAttachments`

Optional tables such as `deletedItems` are probed before use. Required tables and
columns are checked through `ZoteroSchemaStatus` before item reads.

## arXiv Extraction

The first extractor searches, in order:

1. `extra`
2. `url`
3. `DOI`
4. `title`

It recognizes common forms such as:

- `arXiv:1905.10876`
- `arXiv:1905.10876v2`
- `https://arxiv.org/abs/1905.10876`
- `https://arxiv.org/pdf/1905.10876v2.pdf`

The extracted identifier is a local hint. It should not be treated as downloaded
metadata until the user explicitly requests remote arXiv metadata refresh.
