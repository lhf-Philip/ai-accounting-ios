package org.duckdns.lhfser.aiaccounting

import android.content.Context
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.printToString
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.SemanticsActions
import androidx.room.Room
import androidx.lifecycle.Lifecycle
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
        resetComposeHost()
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
        resetComposeHost()
        database.close()
    }

    @Test
    fun directionConversion_appliesAfterImpactPreview() {
        val applied = showEditor()

        selectOthersAdvancedMe()
        previewAndApply()

        composeRule.waitUntil(timeoutMillis = 20_000) { applied.get() }
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

        composeRule.waitUntil(timeoutMillis = 20_000) { applied.get() }
        val updated = runBlocking { repository.getAdvanceCase(advanceCase.advanceCase.id) }
        assertEquals("USD", updated?.advanceCase?.currencyCode)
    }

    @Test
    fun splitLegAndParticipantControls_supportAddAndDelete() {
        showEditor()

        scrollToTag("advance.structural.addPaymentLeg")
        val initialPaymentLegCount = nodeCount("advance.structural.paymentLeg")
        composeRule.onNodeWithTag("advance.structural.addPaymentLeg").performClick()
        scrollToTag("advance.structural.addPaymentLeg")
        waitForNodeCount("advance.structural.paymentLeg", initialPaymentLegCount + 1)
        val addedPaymentLegTag =
            "advance.structural.deletePaymentLeg.$initialPaymentLegCount"
        scrollToTag(addedPaymentLegTag)
        composeRule.onNodeWithTag(addedPaymentLegTag)
            .performSemanticsAction(SemanticsActions.OnClick)
        scrollToTag("advance.structural.addPaymentLeg")
        waitForNodeCount("advance.structural.paymentLeg", initialPaymentLegCount)

        scrollToTag("advance.structural.addParticipant")
        val initialParticipantCount = collectionCount("advance.structural.addParticipant")
        composeRule.onNodeWithTag("advance.structural.addParticipant").performClick()
        scrollToTag("advance.structural.addParticipant")
        waitForCollectionCount(
            "advance.structural.addParticipant",
            initialParticipantCount + 1
        )
        val addedParticipantTag =
            "advance.structural.deleteParticipant.$initialParticipantCount"
        scrollToTag(addedParticipantTag)
        composeRule.onNodeWithTag(addedParticipantTag)
            .performSemanticsAction(SemanticsActions.OnClick)
        scrollToTag("advance.structural.addParticipant")
        waitForCollectionCount("advance.structural.addParticipant", initialParticipantCount)
    }

    @Test
    fun keyboardExit_usesUiAutomatorBackFromFocusedField() {
        showEditor()
        scrollToTag("advance.structural.title")
        composeRule.onNodeWithTag("advance.structural.title")
            .performClick()
            .assertIsFocused()
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).pressBack()
    }

    @Test
    fun cancellingImpactPreview_keepsStoredCaseUnchanged() {
        showEditor()

        selectOthersAdvancedMe()
        composeRule.onNodeWithTag("advance.structural.preview").performClick()
        waitForText("確認套用結構性變更？")
        composeRule.onNodeWithTag("advance.structural.cancelPreview").performClick()

        val unchanged = runBlocking { repository.getAdvanceCase(advanceCase.advanceCase.id) }
        assertEquals("IAdvancedOthers", unchanged?.advanceCase?.direction)
    }

    private fun showEditor(): AtomicBoolean {
        val applied = AtomicBoolean(false)
        resetComposeHost()
        waitForActivityResumed("before-setContent")
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            composeRule.activity.setContent {
                AIAccountingTheme {
                    CompositionLocalProvider(LocalRepository provides repository) {
                        AdvanceStructuralEditorDialog(
                            advanceCase = advanceCase,
                            accounts = listOf(wallet, bank, friend),
                            categories = listOf(food, repaymentCategory),
                            tags = listOf(tag),
                            preloadedTagIds = listOf(tag.id),
                            onDismiss = {},
                            onApplied = { applied.set(true) }
                        )
                    }
                }
            }
        }
        composeRule.waitForIdle()
        waitForActivityResumed("after-setContent")
        waitForGate("editor-root", timeoutMillis = 45_000) {
            hasNode("advance.structural.editor")
        }
        waitForGate("editor-ready", timeoutMillis = 45_000) {
            hasNodeWithReadyState("advance.structural.editor")
        }
        waitForGate("list-mounted", timeoutMillis = 45_000) {
            hasNode("advance.structural.list")
        }
        waitForGate("title-ready", timeoutMillis = 45_000) {
            hasNode("advance.structural.title")
        }
        return applied
    }

    private fun resetComposeHost() {
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            composeRule.activity.setContent {
                Box(Modifier.testTag("advance.structural.emptyHost"))
            }
        }
        composeRule.waitForIdle()
        waitForGate("editor-disposed", timeoutMillis = 20_000) {
            !hasNode("advance.structural.editor") && !hasNode("advance.structural.list")
        }
    }

    private fun previewAndApply() {
        composeRule.onNodeWithTag("advance.structural.preview").performClick()
        waitForText("確認套用結構性變更？")
        composeRule.onNodeWithTag("advance.structural.apply").performClick()
    }

    private fun selectOthersAdvancedMe() {
        composeRule.onNodeWithTag(
            "advance.structural.direction.OthersAdvancedMe"
        ).performClick()
        scrollToTag("advance.structural.repaymentCategory")
        composeRule.onNodeWithTag("advance.structural.repaymentCategory").performClick()
        composeRule.onNodeWithTag(
            "advance.structural.repaymentCategory.option.UITest Food"
        ).performClick()
    }

    private fun waitForTag(tag: String) {
        waitForGate("tag:$tag") {
            composeRule.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun waitForText(text: String) {
        waitForGate("text:$text") {
            composeRule.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun waitForGate(
        gate: String,
        timeoutMillis: Long = 20_000,
        condition: () -> Boolean
    ) {
        try {
            composeRule.waitUntil(timeoutMillis = timeoutMillis, condition = condition)
        } catch (error: androidx.compose.ui.test.ComposeTimeoutException) {
            throw AssertionError(
                "Compose gate '$gate' timed out after ${timeoutMillis}ms.\n" +
                    "Activity state: ${activityStateDescription()}\n" +
                    "Semantics at timeout:\n${dumpSemanticsTree()}",
                error
            )
        }
    }

    private fun waitForActivityResumed(stage: String) {
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        waitForGate("activity-resumed:$stage", timeoutMillis = 30_000) {
            composeRule.activityRule.scenario.state == Lifecycle.State.RESUMED
        }
    }

    private fun hasNode(tag: String): Boolean {
        return composeRule.onAllNodes(hasTestTag(tag), useUnmergedTree = true)
            .fetchSemanticsNodes().isNotEmpty()
    }

    private fun hasNodeWithReadyState(tag: String): Boolean {
        return composeRule.onAllNodes(
            hasTestTag(tag) and androidx.compose.ui.test.hasStateDescription(
                "advance.structural.ready"
            ),
            useUnmergedTree = true
        ).fetchSemanticsNodes().isNotEmpty()
    }

    private fun dumpSemanticsTree(): String {
        val merged = runCatching {
            composeRule.onAllNodes(
                androidx.compose.ui.test.isRoot(),
                useUnmergedTree = false
            ).fetchSemanticsNodes()
        }.getOrElse { emptyList() }
        val unmerged = runCatching {
            composeRule.onAllNodes(
                androidx.compose.ui.test.isRoot(),
                useUnmergedTree = true
            ).fetchSemanticsNodes()
        }.getOrElse { emptyList() }
        val singleRootDump = if (merged.size == 1) {
            runCatching {
                composeRule.onRoot(useUnmergedTree = true).printToString(maxDepth = 60)
            }.getOrElse { dumpError ->
                "<unable to print single root: ${dumpError.message}>"
            }
        } else {
            "<single-root print skipped; merged root count=${merged.size}>"
        }
        fun describeNodes(nodes: List<androidx.compose.ui.semantics.SemanticsNode>): String {
            return nodes.joinToString(separator = "\n") { node ->
                "id=${node.id} bounds=${node.boundsInRoot} config=${node.config}"
            }
        }
        return buildString {
            appendLine("mergedRootCount=${merged.size}")
            appendLine("unmergedRootCount=${unmerged.size}")
            appendLine("mergedRoots=${describeNodes(merged)}")
            appendLine("unmergedRoots=${describeNodes(unmerged)}")
            appendLine(singleRootDump)
        }
    }

    private fun activityStateDescription(): String {
        return runCatching {
            "scenario=${composeRule.activityRule.scenario.state}, " +
                "activity=${composeRule.activity::class.java.name}"
        }.getOrElse { "unavailable: ${it.message}" }
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

    private fun collectionCount(tag: String): Int {
        val description = composeRule.onNodeWithTag(tag)
            .fetchSemanticsNode()
            .config[SemanticsProperties.StateDescription]
        return requireNotNull(description.toIntOrNull()) {
            "Collection '$tag' has invalid stateDescription '$description'"
        }
    }

    private fun nodeCount(tag: String): Int {
        return composeRule.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().size
    }

    private fun waitForNodeCount(tag: String, expected: Int) {
        waitForGate("nodes:$tag=$expected") {
            nodeCount(tag) == expected
        }
    }

    private fun waitForCollectionCount(tag: String, expected: Int) {
        val expectedDescription = expected.toString()
        waitForGate("collection:$tag=$expected") {
            composeRule.onAllNodes(hasTestTag(tag)).fetchSemanticsNodes().any { node ->
                node.config.contains(SemanticsProperties.StateDescription) &&
                    node.config[SemanticsProperties.StateDescription] == expectedDescription
            }
        }
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
