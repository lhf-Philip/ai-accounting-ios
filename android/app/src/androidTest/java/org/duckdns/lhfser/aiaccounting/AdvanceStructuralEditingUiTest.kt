package org.duckdns.lhfser.aiaccounting

import android.content.Context
import androidx.activity.compose.setContent
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performTextReplacement
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import kotlinx.coroutines.runBlocking
import org.duckdns.lhfser.aiaccounting.core.currency.CurrencyService
import org.duckdns.lhfser.aiaccounting.core.model.AccountType
import org.duckdns.lhfser.aiaccounting.core.model.CategoryKind
import org.duckdns.lhfser.aiaccounting.data.db.AIAccountingDatabase
import org.duckdns.lhfser.aiaccounting.data.db.AccountEntity
import org.duckdns.lhfser.aiaccounting.data.db.AdvanceCaseWithDetails
import org.duckdns.lhfser.aiaccounting.data.db.CategoryEntity
import org.duckdns.lhfser.aiaccounting.data.db.TagEntity
import org.duckdns.lhfser.aiaccounting.data.repository.AccountingRepository
import org.duckdns.lhfser.aiaccounting.data.repository.AdvanceParticipantInput
import org.duckdns.lhfser.aiaccounting.ui.LocalRepository
import org.duckdns.lhfser.aiaccounting.ui.screens.AdvanceStructuralEditorDialog
import org.duckdns.lhfser.aiaccounting.ui.theme.AIAccountingTheme
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.math.BigDecimal
import java.time.Instant
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

@RunWith(AndroidJUnit4::class)
class AdvanceStructuralEditingUiTest {
    @get:Rule
    val composeRule = createAndroidComposeRule<StructuralEditorTestActivity>()

    private lateinit var database: AIAccountingDatabase
    private lateinit var repository: AccountingRepository
    private lateinit var advanceCase: AdvanceCaseWithDetails
    private lateinit var wallet: AccountEntity
    private lateinit var bank: AccountEntity
    private lateinit var friend: AccountEntity
    private lateinit var food: CategoryEntity
    private lateinit var repaymentCategory: CategoryEntity
    private lateinit var tag: TagEntity

    @Before
    fun setUp() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        database = Room.inMemoryDatabaseBuilder(context, AIAccountingDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        repository = AccountingRepository(database, CurrencyService(context))
        wallet = account("UITest Cash", AccountType.Cash, 0)
        bank = account("UITest Bank HKD", AccountType.Bank, 1)
        friend = account("UITest Friend Debt", AccountType.Debt, 2)
        food = category("UITest Food", CategoryKind.Expense)
        repaymentCategory = category("UITest Repayment", CategoryKind.Income)
        tag = TagEntity(UUID.randomUUID(), "UITest")

        repository.upsertAccount(wallet)
        repository.upsertAccount(bank)
        repository.upsertAccount(friend)
        repository.upsertCategory(food)
        repository.upsertCategory(repaymentCategory)
        repository.upsertTag(tag)

        val caseId = repository.createAdvanceCase(
            title = "UITest 代墊晚餐",
            date = Instant.parse("2026-06-01T10:00:00Z"),
            currencyCode = "HKD",
            myShareAmount = BigDecimal("50"),
            note = "UITest 代墊案件",
            payerAccount = wallet,
            expenseCategory = food,
            tagIds = listOf(tag.id),
            participants = listOf(AdvanceParticipantInput(friend, BigDecimal("80")))
        )
        val created = requireNotNull(repository.getAdvanceCase(caseId))
        repository.recordAdvanceRepayment(
            advanceCase = created.advanceCase,
            participant = created.participants.single(),
            amount = BigDecimal("20"),
            normalizedAmount = BigDecimal("20"),
            currencyCode = "HKD",
            date = Instant.parse("2026-06-02T10:00:00Z"),
            note = "UITest 代墊還款",
            receiveAccount = bank,
            category = repaymentCategory,
            tagIds = listOf(tag.id)
        )
        advanceCase = requireNotNull(repository.getAdvanceCase(caseId))
    }

    @After
    fun tearDown() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            composeRule.activity.setContent {}
        }
        composeRule.waitForIdle()
        database.close()
    }

    @Test
    fun directionConversion_appliesAfterImpactPreview() {
        val applied = showEditor()

        composeRule.onNodeWithTag(
            "advance.structural.direction.OthersAdvancedMe"
        ).performClick()
        scrollToTag("advance.structural.repaymentCategory")
        composeRule.onNodeWithTag("advance.structural.repaymentCategory").performClick()
        composeRule.onNodeWithTag(
            "advance.structural.repaymentCategory.option.UITest Food"
        ).performClick()
        previewAndApply()

        composeRule.waitUntil(timeoutMillis = 10_000) { applied.get() }
        val updated = runBlocking { repository.getAdvanceCase(advanceCase.advanceCase.id) }
        assertEquals("OthersAdvancedMe", updated?.advanceCase?.direction)
    }

    @Test
    fun currencyChange_requiresConfirmationAndAppliesExplicitAmounts() {
        val applied = showEditor()

        composeRule.onNodeWithTag("advance.structural.currency").performClick()
        composeRule.onNodeWithTag("currency.option.USD").performClick()
        scrollToTag("advance.structural.confirmCurrency")
        composeRule.onNodeWithTag("advance.structural.confirmCurrency").performClick()
        previewAndApply()

        composeRule.waitUntil(timeoutMillis = 10_000) { applied.get() }
        val updated = runBlocking { repository.getAdvanceCase(advanceCase.advanceCase.id) }
        assertEquals("USD", updated?.advanceCase?.currencyCode)
    }

    @Test
    fun splitLegAndParticipantControls_supportAddDeleteAndKeyboardExit() {
        showEditor()

        composeRule.onNodeWithTag("advance.structural.title")
            .performClick()
            .performTextReplacement("UITest 代墊晚餐 UI")
        composeRule.onNodeWithTag("advance.structural.title").assertTextContains("UI")
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).pressBack()
        composeRule.waitForIdle()
        waitForTag("advance.structural.editor")

        composeRule.onAllNodesWithTag("advance.structural.paymentLeg")
            .assertCountEquals(1)
        scrollToTag("advance.structural.addPaymentLeg")
        composeRule.onNodeWithTag("advance.structural.addPaymentLeg").performClick()
        composeRule.onAllNodesWithTag("advance.structural.paymentLeg")
            .assertCountEquals(2)
        scrollToText("刪除此付款來源")
        composeRule.onNodeWithText("刪除此付款來源").performClick()
        composeRule.onAllNodesWithTag("advance.structural.paymentLeg")
            .assertCountEquals(1)

        scrollToTag("advance.structural.participant")
        composeRule.onAllNodesWithTag("advance.structural.participant")
            .assertCountEquals(1)
        scrollToTag("advance.structural.addParticipant")
        composeRule.onNodeWithTag("advance.structural.addParticipant").performClick()
        composeRule.onAllNodesWithTag("advance.structural.participant")
            .assertCountEquals(2)
        scrollToText("刪除此參與人")
        val removeParticipants = composeRule.onAllNodesWithText("刪除此參與人")
        removeParticipants[removeParticipants.fetchSemanticsNodes().lastIndex].performClick()
        composeRule.onAllNodesWithTag("advance.structural.participant")
            .assertCountEquals(1)
    }

    @Test
    fun cancellingImpactPreview_keepsStoredCaseUnchanged() {
        showEditor()

        composeRule.onNodeWithTag(
            "advance.structural.direction.OthersAdvancedMe"
        ).performClick()
        composeRule.onNodeWithTag("advance.structural.preview").performClick()
        waitForText("確認套用結構性變更？")
        composeRule.onNodeWithTag("advance.structural.cancelPreview").performClick()

        val unchanged = runBlocking { repository.getAdvanceCase(advanceCase.advanceCase.id) }
        assertEquals("IAdvancedOthers", unchanged?.advanceCase?.direction)
    }

    private fun showEditor(): AtomicBoolean {
        val applied = AtomicBoolean(false)
        composeRule.setContent {
            AIAccountingTheme {
                CompositionLocalProvider(LocalRepository provides repository) {
                    AdvanceStructuralEditorDialog(
                        advanceCase = advanceCase,
                        accounts = listOf(wallet, bank, friend),
                        categories = listOf(food, repaymentCategory),
                        tags = listOf(tag),
                        onDismiss = {},
                        onApplied = { applied.set(true) }
                    )
                }
            }
        }
        composeRule.waitUntil(timeoutMillis = 10_000) {
            composeRule.onAllNodes(
                hasTestTag("advance.structural.direction.IAdvancedOthers")
            )
                .fetchSemanticsNodes().isNotEmpty()
        }
        return applied
    }

    private fun previewAndApply() {
        composeRule.onNodeWithTag("advance.structural.preview").performClick()
        waitForText("確認套用結構性變更？")
        composeRule.onNodeWithTag("advance.structural.apply").performClick()
    }

    private fun waitForTag(tag: String) {
        composeRule.waitUntil(timeoutMillis = 10_000) {
            composeRule.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun waitForText(text: String) {
        composeRule.waitUntil(timeoutMillis = 10_000) {
            composeRule.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun scrollToTag(tag: String) {
        composeRule.onNodeWithTag("advance.structural.list")
            .performScrollToNode(hasTestTag(tag))
        waitForTag(tag)
    }

    private fun scrollToText(text: String) {
        composeRule.onNodeWithTag("advance.structural.list")
            .performScrollToNode(androidx.compose.ui.test.hasText(text))
        waitForText(text)
    }

    private fun account(name: String, type: AccountType, sortOrder: Int): AccountEntity {
        return AccountEntity(
            id = UUID.randomUUID(),
            name = name,
            currency = "HKD",
            type = type,
            baseBalance = BigDecimal.ZERO,
            sortOrder = sortOrder,
            isArchived = false
        )
    }

    private fun category(name: String, kind: CategoryKind): CategoryEntity {
        return CategoryEntity(
            id = UUID.randomUUID(),
            name = name,
            icon = "circle",
            colorHex = "336699",
            kind = kind
        )
    }
}
