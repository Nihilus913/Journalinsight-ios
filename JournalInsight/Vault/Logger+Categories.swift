// JournalInsight/Vault/Logger+Categories.swift
import os

extension Logger {
    static let vault     = Logger(subsystem: "com.tobias.JournalInsight", category: "vault")
    static let migration = Logger(subsystem: "com.tobias.JournalInsight", category: "migration")
    static let sync      = Logger(subsystem: "com.tobias.JournalInsight", category: "sync")
    static let crypto    = Logger(subsystem: "com.tobias.JournalInsight", category: "crypto")
    static let storage   = Logger(subsystem: "com.tobias.JournalInsight", category: "storage")
}
