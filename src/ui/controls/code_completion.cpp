#include "code_completion.h"
#include "script/cbottoken.h"
#include "CBot/CBotToken.h"
#include <algorithm>

namespace Ui {

CCodeCompletion::CCodeCompletion() {}
CCodeCompletion::~CCodeCompletion() {}

std::vector<CompletionItem> CCodeCompletion::GetCompletions(
    const std::string& partialWord,
    const std::string& context,
    const std::vector<CompletionItem>& extra)
{
    std::vector<CompletionItem> result;

    std::string prefix = partialWord;
    std::transform(prefix.begin(), prefix.end(), prefix.begin(), ::tolower);

    if (context == "object.") {
        AddMembers(result, prefix);
    } else if (context == "point.") {
        AddPointMembers(result, prefix);
    } else if (!context.empty()) {
        // Primitive / unknown-primitive member access (e.g. int, float): no members.
    } else {
        AddKeywords(result, prefix);
        AddBuiltinFunctions(result, prefix);
        AddTypes(result, prefix);
        AddConstants(result, prefix);
        for (const auto& e : extra) {
            if (MatchPrefix(e.displayLabel, prefix)) result.push_back(e);
        }
    }

    std::sort(result.begin(), result.end(),
        [](const CompletionItem& a, const CompletionItem& b) {
            return a.displayLabel < b.displayLabel;
        });

    if (result.size() > 100) result.resize(100);  // popup scrolls; keep bounded
    return result;
}

void CCodeCompletion::AddKeywords(std::vector<CompletionItem>& out, const std::string& prefix)
{
    // CBotToken::GetKeyWord() does name->TokenId lookup
    // We need to iterate all keywords; they're in a bimap in CBotToken.cpp
    // For now, hardcode the common ones (will improve)
    const char* keywords[] = {
        "if", "else", "while", "for", "break", "continue", "return",
        "int", "float", "bool", "string", "void", "class", "public", "private",
        "true", "false", "null", "new", "delete", "this", "static"
    };

    for (const auto& kw : keywords) {
        if (MatchPrefix(kw, prefix)) {
            out.push_back({
                CompletionItem::Keyword,
                kw,
                kw,
                ""
            });
        }
    }
}

void CCodeCompletion::AddBuiltinFunctions(std::vector<CompletionItem>& out, const std::string& prefix)
{
    // IsFunction() checks against hardcoded list in cbottoken.cpp
    // Extract common ones for completion
    const char* functions[] = {
        "sin", "cos", "tan", "sqrt", "pow", "abs", "floor", "ceil", "rand",
        "goto", "move", "turn", "grab", "drop", "fire", "radar", "distance",
        "wait", "message", "motor", "open", "close", "eof", "writeln", "readln",
        "strlen", "strleft", "strright", "strmid", "strval", "strlower", "strupper",
        "isbusy", "isexist", "isshooting"
    };

    for (const auto& fn : functions) {
        if (MatchPrefix(fn, prefix)) {
            out.push_back({
                CompletionItem::BuiltinFunction,
                std::string(fn) + "()",
                fn,
                ""
            });
        }
    }
}

void CCodeCompletion::AddTypes(std::vector<CompletionItem>& out, const std::string& prefix)
{
    const char* types[] = {
        "void", "byte", "short", "char", "int", "long", "float", "double",
        "bool", "string", "point", "object", "file"
    };

    for (const auto& t : types) {
        if (MatchPrefix(t, prefix)) {
            out.push_back({
                CompletionItem::Type,
                t,
                t,
                ""
            });
        }
    }
}

void CCodeCompletion::AddMembers(std::vector<CompletionItem>& out, const std::string& prefix)
{
    // Fields of the CBot "object" class (scriptfunc.cpp) plus point's x/y/z.
    const char* members[] = {
        "category", "position", "orientation", "pitch", "roll",
        "energyLevel", "shieldLevel", "temperature", "altitude", "lifeTime",
        "energyCell", "load", "id", "team", "dead", "velocity"
    };

    for (const auto& m : members) {
        if (MatchPrefix(m, prefix)) {
            out.push_back({ CompletionItem::Member, m, m, "" });
        }
    }
}

void CCodeCompletion::AddPointMembers(std::vector<CompletionItem>& out, const std::string& prefix)
{
    const char* members[] = { "x", "y", "z" };
    for (const auto& m : members) {
        if (MatchPrefix(m, prefix)) {
            out.push_back({ CompletionItem::Member, m, m, "" });
        }
    }
}

void CCodeCompletion::AddConstants(std::vector<CompletionItem>& out, const std::string& prefix)
{
    // Game-defined CBot constants (object categories, filters, colors...),
    // registered via CBotProgram::DefineNum -> CBotToken.
    for (const auto& kv : CBot::CBotToken::GetDefineNums()) {
        if (MatchPrefix(kv.first, prefix)) {
            out.push_back({ CompletionItem::Constant, kv.first, kv.first, "" });
        }
    }
}

bool CCodeCompletion::MatchPrefix(const std::string& item, const std::string& prefix) const
{
    if (prefix.empty()) return true;
    std::string lower_item = item;
    std::transform(lower_item.begin(), lower_item.end(), lower_item.begin(), ::tolower);
    return lower_item.substr(0, prefix.size()) == prefix;
}

}
