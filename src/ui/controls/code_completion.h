#pragma once

#include <string>
#include <vector>
#include <memory>

namespace Ui {

struct CompletionItem {
    enum Type { Keyword, Function, BuiltinFunction, Type, Variable, Member, Constant } type;
    std::string text;             // wstawić
    std::string displayLabel;     // wyświetlić (może być inny niż text)
    std::string hint;             // krótki opis
};

class CCodeCompletion {
public:
    CCodeCompletion();
    ~CCodeCompletion();

    std::vector<CompletionItem> GetCompletions(
        const std::string& partialWord,
        const std::string& context = "",   // "" | "object." | "point." | "<primitive>."
        const std::vector<CompletionItem>& extra = {}  // user-defined symbols
    );

private:
    void AddKeywords(std::vector<CompletionItem>& out, const std::string& prefix);
    void AddBuiltinFunctions(std::vector<CompletionItem>& out, const std::string& prefix);
    void AddTypes(std::vector<CompletionItem>& out, const std::string& prefix);
    void AddMembers(std::vector<CompletionItem>& out, const std::string& prefix);
    void AddPointMembers(std::vector<CompletionItem>& out, const std::string& prefix);
    void AddConstants(std::vector<CompletionItem>& out, const std::string& prefix);
    bool MatchPrefix(const std::string& item, const std::string& prefix) const;
};

}
