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
    static var schemas: [any VersionedSchema.Type] {
        [AccountingSchemaV1.self, AccountingSchemaV2.self, AccountingSchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            // Do not read V2.Category.kind here: an automatic migration can leave it missing.
            .lightweight(fromVersion: AccountingSchemaV1.self, toVersion: AccountingSchemaV2.self),
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
