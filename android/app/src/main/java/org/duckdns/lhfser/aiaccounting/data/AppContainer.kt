package org.duckdns.lhfser.aiaccounting.data

import android.content.Context
import androidx.room.Room
import org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService
import org.duckdns.lhfser.aiaccounting.data.db.AIAccountingDatabase
import org.duckdns.lhfser.aiaccounting.data.db.SeedData
import org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository

class AppContainer(context: Context) {
    private val appContext = context.applicationContext

    val database: AIAccountingDatabase by lazy {
        Room.databaseBuilder(appContext, AIAccountingDatabase::class.java, "ai_accounting.db")
            .addMigrations(AIAccountingDatabase.MIGRATION_1_2)
            .addMigrations(AIAccountingDatabase.MIGRATION_2_3)
            .addCallback(SeedData.callback(appContext))
            .build()
    }

    val repository: AccountingRepository by lazy {
        AccountingRepository(database, currencyService)
    }

    val currencyService: CurrencyService by lazy {
        CurrencyService(appContext)
    }
}
