#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/cache
sources=(Sources/*.swift)
sources=("${(@)sources:#Sources/Main.swift}")
for suite in Core Gemini Editor Reply ConversationReply CodeReply CodeSegment Table TranslationContext Paragraph Protection CredentialAccess KeychainPolicy Permission TranslationPipeline Model Usage UsageMonitor UsageAccount Optimization SupportOptimization BridgeProtocol IncrementalReply OptimizationLifecycle StageReplay StructureEdge HealthManifest ReadRecovery FidelityFallback ReviewRegression TranslationQuality ServiceRecovery ConnectionRouting CLIDelivery CLIInteraction ManualBinding LocalizedReply WebUsageSetup WebCodeRoute ManagedWeb NativeUsageParser NativeWebUsage StreamingIntegration; do
    swiftc -swift-version 5 -module-cache-path "$PWD/.build/cache" "${sources[@]}" "Tests/${suite}Tests.swift" -o ".build/${suite}-tests"
    ".build/${suite}-tests" --simulation
done
