import Foundation
import SwiftUI
import Translation

/// Operational TUI text is ephemeral and must never become an assistant reply.
/// This parser uses bottom-of-surface text, not fonts or terminal app names.
enum CLIInteractionPolicy {
    enum Kind: String { case selection, permission, status }
    struct Choice: Equatable { let key: String; let label: String }
    struct Notice: Equatable {
        let kind: Kind
        let title: String
        let details: String
        let choices: [Choice]
        let original: String
        var identity: String { [kind.rawValue, title, details].joined(separator:"\n") + choices.map { "\n" + $0.key + $0.label }.joined() }
    }
    static func notice(screen: String) -> Notice? {
        guard screen.utf16.count <= 500_000, !screen.unicodeScalars.contains(where: { $0.value == 27 }) else { return nil }
        var lines = Array(CLIPromptPolicy.terminalLines(screen).suffix(40))
        // Only known TUI chrome may follow a current notice. A shell or new
        // composer after an old menu remains a nonblank boundary.
        while let last=lines.last, chrome(last) { lines.removeLast() }
        guard let last=lines.last else { return nil }
        let runningPattern = #"^\s*[✻✽✶✳⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏]\s+(?:.+(?:ctrl\+c to interrupt|esc to interrupt).*|(?:Thinking|Working|Running|Reading|Compacting|Cooking|Crunching|Churning|Computing|Executing|Searching)[.…]+\s*\([0-9]+s\s*·\s*[↑↓] [0-9]+ tokens?\))$"#
        if last.range(of:runningPattern,options:[.regularExpression,.caseInsensitive]) != nil {
            var title=String(last.trimmingCharacters(in:.whitespaces).dropFirst()).trimmingCharacters(in:.whitespaces)
            title=title.replacingOccurrences(of:#"\s*\([0-9]+s\s*·\s*[↑↓] [0-9]+ tokens?\)$"#,with:"",options:.regularExpression)
            return .init(kind:.status,title:title,details:"",choices:[],original:last)
        }
        // A menu has a recognizable heading, at least two numbered choices,
        // and a navigation hint or active choice cursor. Prose lists alone are
        // insufficient. Cursor position is deliberately excluded from identity.
        let navigation = last.range(of:#"(?i)^(?:Enter to (?:confirm|select|continue).*(?:Esc|escape).+|(?:Esc|escape) to cancel.*|Use (?:arrow keys|↑/↓).*)$"#,options:.regularExpression) != nil
        if navigation { lines.removeLast() }
        guard !lines.isEmpty else { return nil }
        let pattern=#"^\s*(❯\s*)?([0-9]{1,2}[.)])\s+(.+)$"#
        let regex=try! NSRegularExpression(pattern:pattern)
        var choices:[Choice]=[], optionStart=lines.count, cursor=false
        for i in lines.indices.reversed() {
            let line=lines[i], ns=line as NSString
            guard let match=regex.firstMatch(in:line,range:NSRange(location:0,length:ns.length)) else { break }
            cursor = cursor || match.range(at:1).location != NSNotFound
            choices.insert(.init(key:ns.substring(with:match.range(at:2)),label:ns.substring(with:match.range(at:3))),at:0)
            optionStart=i
        }
        guard choices.count >= 2, choices.count <= 12, Set(choices.map(\.key)).count == choices.count,
              navigation || cursor, optionStart > 0 else { return nil }
        let headings=#"(?i)^(?:Do you want to .+\?|Do you trust .+\?|Would you like to .+\?|Allow .+\?|Trust .+\?|Select (?:model|an option|a model|permission mode|.+ for .+)|Choose (?:a model|an option|.+)|(?:Which|What|How|Should) .+\?)$"#
        guard let start=lines[..<optionStart].lastIndex(where: { $0.trimmingCharacters(in:.whitespaces).range(of:headings,options:.regularExpression) != nil }) else { return nil }
        // Reject an input prompt between the heading and options.
        guard !lines[(start+1)..<optionStart].contains(where: { $0.trimmingCharacters(in:.whitespaces).hasPrefix("❯") }) else { return nil }
        let title=lines[start].trimmingCharacters(in:.whitespaces)
        let permission=title.range(of:#"(?i)^(?:Do you want to (?:proceed|allow)|Do you trust |Allow |Trust )"#,options:.regularExpression) != nil
        let commandStart=permission ? lines[max(0,start-8)..<start].lastIndex(where: {
            $0.trimmingCharacters(in:.whitespaces).range(of:#"(?i)^(?:Bash command|Read file|Write file|Edit file|Tool use|Command)$"#,options:.regularExpression) != nil
        }) : nil
        let details=(commandStart.map {Array(lines[$0..<start])} ?? []) + Array(lines[(start+1)..<optionStart])
        let detailText=details.joined(separator:"\n")
        guard title.count <= 300, detailText.count <= 2000, choices.allSatisfy({$0.label.count <= 500}) else { return nil }
        let original=lines[(commandStart ?? start)...].joined(separator:"\n") + (navigation ? "\n"+last : "")
        return .init(kind:permission ? .permission:.selection,title:title,details:detailText,choices:choices,original:original)
    }
    private static func chrome(_ raw:String) -> Bool {
        let line=raw.trimmingCharacters(in:.whitespaces)
        return line.isEmpty || line.hasPrefix("A畜伴侣 CLI · ") || CLIPromptPolicy.isHint(line) ||
            (line.count >= 3 && line.allSatisfy { "─━═".contains($0) })
    }
}

/// Own translation task/session: prompts do not steal reply or outgoing jobs.
/// Local system translation keeps command details out of cloud translation.
@MainActor final class CLINoticeMonitor: ObservableObject {
    @Published private(set) var notice: CLIInteractionPolicy.Notice?
    @Published private(set) var chinese = ""
    @Published private(set) var status = ""
    @Published private(set) var configuration: TranslationSession.Configuration?
    @Published private(set) var systemTaskID: UUID?
    var translate: (@MainActor (String) async throws -> String)?
    private var leased=false
    private var lastRead:TimeInterval?
    private var stable=0
    private var translatedIdentity:String?
    private var generation=UUID()
    private var work:Task<Void,Never>?
    private var polling:Task<Void,Never>?
    private var continuation:CheckedContinuation<TranslationSession,Error>?
    private var activeSession:TranslationSession?

    func start(read:@escaping @MainActor () -> (String?, Bool), current:@escaping @MainActor () -> Bool) {
        stop()
        polling=Task { [weak self] in
            while !Task.isCancelled {
                guard let self, current() else { self?.reset(); return }
                let (screen,matched)=read()
                observe(screen:screen,identityValid:screen != nil,matchingFooter:matched,now:Date().timeIntervalSinceReferenceDate)
                do { try await Task.sleep(for:.milliseconds(500)) } catch { return }
            }
        }
    }
    func stop() { polling?.cancel();polling=nil;reset() }
    func observe(screen:String?,identityValid:Bool,matchingFooter:Bool,now:TimeInterval) {
        guard identityValid, let screen else {reset();return}
        if let lastRead, now-lastRead > 2 {reset()}
        self.lastRead=now
        if matchingFooter {leased=true}
        else if screen.contains("A畜伴侣 CLI · ") { reset();return }
        guard leased else { return }
        guard let next=CLIInteractionPolicy.notice(screen:screen) else {clearNotice();return}
        if notice?.identity != next.identity {
            clearNotice();notice=next;stable=1
            status="原提示已读取，等待稳定后翻译…"
            return
        }
        notice=next
        stable += 1
        guard stable >= 2, translatedIdentity != next.identity else {return}
        translatedIdentity=next.identity
        let token=generation
        status="正在用系统翻译转换 CLI 提示…"
        work=Task { [weak self] in
            guard let self else {return}
            do {
                var parts=[try await translated(next.title)]
                // Commands and arguments are display-only, verbatim. Translate
                // the question and option labels, never execute a choice.
                if !next.details.isEmpty {parts.append(next.details)}
                for choice in next.choices {parts.append(choice.key+" "+(try await translated(choice.label)))}
                try Task.checkCancellation()
                guard generation == token,notice?.identity == next.identity else {return}
                chinese=parts.joined(separator:"\n");status="提示已译为中文；请在原 CLI 中操作。"
            } catch {
                guard generation == token,notice?.identity == next.identity else {return}
                status="提示翻译暂不可用，原文已保留。"
            }
        }
    }
    func retry() {
        guard let notice else {return}
        translatedIdentity=nil;stable=1
        // Preserve the capture lease; retry does not authorize any input.
        observe(screen:notice.original,identityValid:true,matchingFooter:false,now:lastRead ?? 0)
    }
    private func translated(_ text:String) async throws -> String {
        try await TextTranslation.runProtected(text) { [self] part in
            if let translate {return try await translate(part)}
            let session=try await systemSession()
            return try await SystemTranslationProtection.translate(part,toChinese:true) {try await session.translate($0).targetText}
        }
    }
    private func systemSession() async throws -> TranslationSession {
        if let activeSession {return activeSession}
        let from=Locale.Language(identifier:"en"),to=Locale.Language(identifier:"zh-Hans")
        let installed=try await TextTranslation.withDeadline(timeout:.seconds(10)) {await LanguageAvailability().status(from:from,to:to) == .installed ? "yes":"no"}
        try Task.checkCancellation()
        if installed == "yes", #available(macOS 26.0, *) {
            let session=TranslationSession(installedSource:from,target:to);activeSession=session;return session
        }
        systemTaskID=UUID();configuration = .init(source:from,target:to)
        var prepared:TranslationSession?
        do {
            _ = try await TextTranslation.withDeadline(timeout:.seconds(120)) {
                prepared=try await withCheckedThrowingContinuation {self.continuation=$0};return "ready"
            }
            guard let prepared else {throw CancellationError()};activeSession=prepared;return prepared
        } catch {cancelSystem();throw error}
    }
    func runSystem(_ session:TranslationSession,attempt:UUID) async {
        guard systemTaskID == attempt,continuation != nil else {return}
        do {
            _ = try await TextTranslation.withDeadline {try await session.prepareTranslation();return ""}
            guard systemTaskID == attempt else {return}
            let pending=continuation;continuation=nil;pending?.resume(returning:session)
        } catch {
            guard systemTaskID == attempt else {return}
            let pending=continuation;continuation=nil;pending?.resume(throwing:error)
        }
    }
    private func cancelSystem() {
        continuation?.resume(throwing:CancellationError());continuation=nil
        if #available(macOS 26.0, *) {activeSession?.cancel()}
        activeSession=nil;configuration=nil;systemTaskID=nil
    }
    private func clearNotice() {
        generation=UUID();work?.cancel();work=nil;cancelSystem()
        notice=nil;chinese="";status="";stable=0;translatedIdentity=nil
    }
    func reset() {leased=false;lastRead=nil;clearNotice()}
}

struct CLINoticeView:View {
    @ObservedObject var monitor:CLINoticeMonitor
    var fontSize:CGFloat
    var body:some View {
        Group {
            if let notice=monitor.notice {
                VStack(alignment:.leading,spacing:5) {
                    Label(notice.kind == .status ? "CLI 运行提示":"CLI 需要你选择",systemImage:notice.kind == .status ? "terminal":"list.number")
                        .font(.system(size:11,weight:.semibold))
                    ScrollView {
                        VStack(alignment:.leading,spacing:5) {
                            Text(monitor.chinese.isEmpty ? notice.original:monitor.chinese)
                                .font(.system(size:fontSize)).textSelection(.enabled)
                                .frame(maxWidth:.infinity,alignment:.leading)
                            if !monitor.chinese.isEmpty {
                                DisclosureGroup("原提示") {Text(notice.original).font(.system(size:12)).textSelection(.enabled)}
                            }
                        }
                    }.frame(height: min(120, max(64, CGFloat((monitor.chinese.isEmpty ? notice.original:monitor.chinese).components(separatedBy:.newlines).count) * fontSize * 1.5 + 24)))
                        .scrollIndicators(.visible)
                    HStack {
                        Text(monitor.status).font(.system(size:10)).foregroundStyle(.secondary)
                        Spacer()
                        if monitor.status.contains("暂不可用") {Button("重试翻译"){monitor.retry()}.controlSize(.mini)}
                    }
                }.padding(10).background(Color.accentColor.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
            }
        }.background {
            if let attempt=monitor.systemTaskID,let configuration=monitor.configuration {
                Color.clear.frame(width:0,height:0).translationTask(configuration) {session in await monitor.runSystem(session,attempt:attempt)}.id(attempt)
            }
        }
    }
}
