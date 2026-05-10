from __future__ import annotations

from bilin_api.schemas import ProviderPreset, ProviderProtocol

PROVIDER_PRESETS: tuple[ProviderPreset, ...] = (
    ProviderPreset(
        id="openai",
        name="OpenAI",
        protocol=ProviderProtocol.openai_compatible,
        base_url="https://api.openai.com/v1",
        metadata={"docs_url": "https://platform.openai.com/docs/api-reference"},
    ),
    ProviderPreset(
        id="anthropic",
        name="Anthropic",
        protocol=ProviderProtocol.anthropic_compatible,
        base_url="https://api.anthropic.com",
        metadata={"docs_url": "https://docs.anthropic.com/en/api/overview"},
    ),
    ProviderPreset(
        id="deepseek",
        name="DeepSeek",
        protocol=ProviderProtocol.openai_compatible,
        base_url="https://api.deepseek.com",
        metadata={"docs_url": "https://api-docs.deepseek.com/"},
    ),
    ProviderPreset(
        id="gemini",
        name="Google Gemini",
        protocol=ProviderProtocol.openai_compatible,
        base_url="https://generativelanguage.googleapis.com/v1beta/openai/",
        metadata={"docs_url": "https://ai.google.dev/gemini-api/docs/openai"},
    ),
    ProviderPreset(
        id="qwen-dashscope-cn",
        name="Qwen DashScope (Beijing)",
        protocol=ProviderProtocol.openai_compatible,
        base_url="https://dashscope.aliyuncs.com/compatible-mode/v1",
        metadata={
            "region": "cn-beijing",
            "docs_url": (
                "https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope"
            ),
        },
    ),
    ProviderPreset(
        id="qwen-dashscope-us",
        name="Qwen DashScope (Virginia)",
        protocol=ProviderProtocol.openai_compatible,
        base_url="https://dashscope-us.aliyuncs.com/compatible-mode/v1",
        metadata={
            "region": "us-east-1",
            "docs_url": (
                "https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope"
            ),
        },
    ),
    ProviderPreset(
        id="qwen-dashscope-intl",
        name="Qwen DashScope (Singapore)",
        protocol=ProviderProtocol.openai_compatible,
        base_url="https://dashscope-intl.aliyuncs.com/compatible-mode/v1",
        metadata={
            "region": "ap-southeast-1",
            "docs_url": (
                "https://help.aliyun.com/zh/model-studio/compatibility-of-openai-with-dashscope"
            ),
        },
    ),
    ProviderPreset(
        id="kimi-cn",
        name="Kimi (China)",
        protocol=ProviderProtocol.openai_compatible,
        base_url="https://api.moonshot.cn/v1",
        metadata={"docs_url": "https://platform.moonshot.cn/docs/api/chat"},
    ),
    ProviderPreset(
        id="kimi-global",
        name="Kimi (Global)",
        protocol=ProviderProtocol.openai_compatible,
        base_url="https://api.moonshot.ai/v1",
        metadata={"docs_url": "https://platform.kimi.ai/docs/api/overview"},
    ),
    ProviderPreset(
        id="groq",
        name="Groq",
        protocol=ProviderProtocol.openai_compatible,
        base_url="https://api.groq.com/openai/v1",
        metadata={"docs_url": "https://console.groq.com/docs/"},
    ),
    ProviderPreset(
        id="openrouter",
        name="OpenRouter",
        protocol=ProviderProtocol.openai_compatible,
        base_url="https://openrouter.ai/api/v1",
        metadata={"docs_url": "https://openrouter.ai/docs/quickstart"},
    ),
    ProviderPreset(
        id="xai",
        name="xAI",
        protocol=ProviderProtocol.openai_compatible,
        base_url="https://api.x.ai/v1",
        metadata={"docs_url": "https://docs.x.ai/docs/guides/chat-completions"},
    ),
)
