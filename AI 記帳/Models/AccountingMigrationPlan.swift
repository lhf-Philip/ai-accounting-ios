import Foundation
import SwiftData

// This is the live schema. Freeze its model definitions before a future schema change.
enum AccountingSchemaV3: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(3, 0, 0) }
    static var models: [any PersistentModel.Type] {
        [Account.self, FinancialTransaction.self, Category.self, Tag.self, Shortcut.self,
         RecurringRule.self, RecurringOccurrence.self, CategoryMonthlyBudget.self,
         BudgetMonthlyHistory.self, BudgetSettings.self, AdvanceCase.self,
         AdvanceParticipant.self, AdvanceRepayment.self]
    }
}

enum AccountingMigrationPlan: SchemaMigrationPlan {
    // These are distinct historical persisted structures, not every Git commit or app version.
    // Ordered stages also recognize stores that skipped app releases during automatic migration.
    private static var legacySchemas: [any VersionedSchema.Type] {
        [AccountingSchemaV1.self,
         AccountingSchemaTransfer.self,
         AccountingSchemaBudget.self,
         AccountingSchemaAdvance.self,
         AccountingSchemaAdvanceLinks.self,
         AccountingSchemaHistory.self,
         AccountingSchemaSettings.self,
         AccountingSchemaRecurring.self,
         AccountingSchemaPreV2.self,
         AccountingSchemaV2.self]
    }

    static var schemas: [any VersionedSchema.Type] {
        legacySchemas + [AccountingSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        // Never read required enum/array getters in an intermediate schema: earlier automatic
        // migrations can leave newly introduced values missing. Normalize only in the live schema.
        zip(legacySchemas, legacySchemas.dropFirst()).map { source, destination in
            MigrationStage.lightweight(fromVersion: source, toVersion: destination)
        } + [
            .custom(fromVersion: AccountingSchemaV2.self, toVersion: AccountingSchemaV3.self,
                    willMigrate: nil, didMigrate: { context in
                let categories = try context.fetch(FetchDescriptor<Category>())
                for category in categories where category.storedKind == nil {
                    category.storedKind = .both
                }
                // A migration save failure must reach startup recovery, not report readiness.
                if context.hasChanges { try context.save() }
            })
        ]
    }
}
