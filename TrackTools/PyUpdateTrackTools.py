import re
import requests
from pathlib import Path

# =========================
# Configuration
# =========================

SUPPORTED_EXTENSIONS = {".7z", ".zip", ".rar", ".exe"}
TARGET_MD_NAME = "Win DailyUse Track Tools.md"

HEADERS = {
    "User-Agent": "WinToolsTableGenerator/1.0"
}

# =========================
# Tool name normalization
# =========================

def normalize_tool_name(filename: str) -> str:
    """
    Convert archive filename into a clean human-readable tool name.
    Examples:
        DiskGeniusPro_x64.7z -> DiskGenius Pro
        DownKyi_B站下载.7z  -> DownKyi
    """
    name = Path(filename).stem

    # Remove architecture and OS markers
    name = re.sub(r"(x64|x86|win32|win64)", "", name, flags=re.I)

    # Remove version numbers
    name = re.sub(r"v?\d+(\.\d+)*", "", name, flags=re.I)

    # Remove Chinese annotations or extra notes
    name = re.split(r"[_\-（(]", name)[0]

    # Normalize separators
    name = re.sub(r"[._\-]+", " ", name)

    return name.strip().title()

# =========================
# Tool function lookup
# =========================

def query_tool_function(tool_name: str) -> str:
    """
    Query real tool function using public APIs.
    Priority order:
        1. Wikipedia REST API
        2. DuckDuckGo Instant Answer API
        3. Fallback description
    """

    # Wikipedia API
    wiki_api = f"https://en.wikipedia.org/api/rest_v1/page/summary/{tool_name.replace(' ', '_')}"
    try:
        r = requests.get(wiki_api, headers=HEADERS, timeout=5)
        if r.status_code == 200:
            data = r.json()
            if data.get("extract"):
                return data["extract"].split(".")[0]
    except Exception:
        pass

    # DuckDuckGo Instant Answer API
    try:
        ddg_api = "https://api.duckduckgo.com/"
        r = requests.get(
            ddg_api,
            params={
                "q": tool_name,
                "format": "json",
                "no_redirect": 1,
                "no_html": 1
            },
            timeout=5
        )
        data = r.json()
        if data.get("AbstractText"):
            return data["AbstractText"].split(".")[0]
    except Exception:
        pass

    # Safe fallback
    return "Windows utility tool"

# =========================
# Markdown generation
# =========================

def build_markdown_table(tools: list[tuple[str, str]]) -> str:
    """
    Build Markdown table text.
    """
    lines = [
        "| Name | Function |",
        "| ---- | -------- |"
    ]
    for name, function in tools:
        lines.append(f"| {name} | {function} |")

    return "\n".join(lines)

# =========================
# Markdown update logic
# =========================

def update_markdown_file(md_path: Path, table_content: str):
    """
    Update or append the tool table in the target Markdown file.
    """
    if md_path.exists():
        original_content = md_path.read_text(encoding="utf-8")

        # Replace existing table if found
        if "| Name | Function |" in original_content:
            updated_content = re.sub(
                r"\| Name \| Function \|[\s\S]*?$",
                table_content,
                original_content,
                flags=re.MULTILINE
            )
        else:
            updated_content = original_content + "\n\n" + table_content
    else:
        updated_content = table_content

    md_path.write_text(updated_content, encoding="utf-8")

# =========================
# Main execution
# =========================

def main():
    # Directory where THIS SCRIPT file is located
    script_dir = Path(__file__).resolve().parent

    # Tools are located in the same directory as the script
    tools_dir = script_dir

    # Markdown file is located in the parent directory of the script
    markdown_path = script_dir.parent / TARGET_MD_NAME

    collected_tools = []

    for item in tools_dir.iterdir():
        if item.is_file() and item.suffix.lower() in SUPPORTED_EXTENSIONS:
            tool_name = normalize_tool_name(item.name)
            function = query_tool_function(tool_name)
            collected_tools.append((tool_name, function))

    # Sort tools alphabetically by name
    collected_tools.sort(key=lambda x: x[0].lower())

    markdown_table = build_markdown_table(collected_tools)
    update_markdown_file(markdown_path, markdown_table)

    print("✅ Tool table successfully generated and updated.")
    print(f"📄 Target file: {markdown_path}")

if __name__ == "__main__":
    main()
