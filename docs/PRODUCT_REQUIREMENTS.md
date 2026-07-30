# AI Accounting Product Requirements

Status: Discovery questionnaire
Last updated: 2026-07-30
Applies to: Product scope, iOS, Android, data model, migration, UX, performance, and release decisions

## Purpose

This document captures the product the owner actually wants before further bug fixing or feature development. It deliberately asks about trade-offs, unwanted functionality, data compatibility, and edge cases so that the existing implementation does not silently define the future product.

## How to answer

- Answer by question number. Short answers are acceptable.
- Use `Keep`, `Simplify`, `Remove`, or `Unsure` where applicable.
- Use `Must`, `Should`, `Could`, or `Won't` to indicate priority.
- For anything that should remain exactly as it currently works, answer `Keep current behaviour`.
- For anything not understood yet, answer `Unsure`; do not invent a requirement.
- Real examples of incorrect balances, confusing screens, or unwanted behaviour are especially useful.

---

## A. Product identity and success

1. In one sentence, what should AI Accounting help you accomplish?
2. Is this app primarily for you alone, for friends/family, or for eventual public App Store users?
3. What is the single most important daily workflow?
4. What are the three outcomes that would make the app feel successful?
5. What existing apps or workflows should it replace for you?
6. Which current features feel like they were added because they were possible rather than because you needed them?
7. Which current behaviour makes you distrust the app most?
8. If the app could become excellent at only one area, should it be fast entry, accurate balances, debt/advance tracking, budgeting, reports, or backup safety?
9. Should the product remain a personal ledger, or are you trying to build a more formal accounting system?
10. What must this app explicitly never become?

## B. Platform and distribution scope

11. Should the project now be iOS-only, or must Android remain actively maintained?
12. If Android remains, should parity be strict, feature-subset parity, or independent platform development?
13. Would you accept freezing Android until iOS is stable?
14. Do you need iPhone only, or also native iPad layouts?
15. Do you want macOS, Apple Watch, widgets, Shortcuts/App Intents, or none of these?
16. Is App Store release an actual goal, a possible future goal, or not a goal?
17. Must the app work completely offline?
18. Do you eventually need live cross-device sync, or is backup/restore sufficient?
19. If sync is wanted, should it use iCloud/CloudKit, your own server, WebDAV, or remain undecided?
20. What is the oldest iOS version and oldest device you genuinely need to support?

## C. Existing data and migration risk

21. Is the current production data real and irreplaceable, test data, or a mixture?
22. Approximately how many accounts, transactions, advance cases, repayments, tags, and years of history exist?
23. Which existing backup versions must still import successfully?
24. Is preserving every historical field more important than simplifying the future model?
25. Would you accept a one-time guided migration that permanently converts old data to a cleaner format?
26. Would you accept removing legacy compatibility after a verified migration and backup?
27. Would you ever accept starting with a clean database if the old data is exported into a readable archive?
28. Should JSON backup be the long-term recovery contract, or should the database itself be treated as canonical?
29. Must export → import → export preserve exact IDs and links, or only the visible financial meaning?
30. How much audit history is required: none, last edit only, full change history, or undo for a limited period?
31. When data is inconsistent, should the app auto-repair, block and explain, or offer a preview before repair?
32. Should startup ever modify financial data automatically?
33. If migration fails, should the app refuse to open, open read-only, or offer recovery/reset choices?

## D. Core accounting model

34. Which account types are truly required: cash, bank, credit card, debt/person, stored value, investment, or others?
35. Should a debt account represent one person, one debt agreement, or a generic amount owed?
36. Should credit-card balances be displayed as positive amount owed, negative net worth, or configurable?
37. What should `base balance` mean, and should users still be able to edit it after transactions exist?
38. Should account balance always equal opening balance plus all posted ledger entries?
39. Do you need pending transactions, reconciled transactions, or statement balances?
40. Can a transaction currency differ from its account currency?
41. If yes, must the app store the actual account-currency impact and exchange rate used?
42. Do you need historical exchange rates, or are current-rate estimates acceptable for reports?
43. Should fees, cashback, rebates, interest, and adjustments be first-class transaction concepts?
44. Should categories and tags remain separate? What is the intended difference?
45. Can one transaction have multiple categories or split amounts?
46. Which financial rules must never be inferred from note text?

## E. Ordinary income and expense entry

47. What fields are required for the fastest normal entry?
48. Should users type all amounts as positive and choose income/expense, or see signed amounts?
49. Should the selected account restrict which transaction types are allowed?
50. Should date/time default to now, and how often do you enter historical transactions?
51. Are photos/receipts required, optional, or removable?
52. Do you need merchant/payee as a separate field from notes?
53. Do you need location, payment method, tax, quantity, or none of these?
54. Should editing an ordinary transaction be allowed without restrictions?
55. When deleting a transaction that affects budgets, balances, debt, or reports, what warning is required?
56. Should duplicate detection exist? If yes, what counts as a likely duplicate?
57. Which search fields are necessary: note, merchant, category, tag, amount, account, date, currency, person?
58. Should the ledger support pagination/infinite scrolling instead of loading all history?

## F. Transfers and account adjustments

59. Do you only need simple account-to-account transfers, or genuine split/merge transfers?
60. Is same-account cross-currency transfer a real use case?
61. Do transfers need separate sent amount, received amount, rate, and fee?
62. Should transfer fees become an expense automatically?
63. Must users be able to structurally edit a transfer after creation?
64. If a complex transfer is edited, is rebuilding all linked legs acceptable?
65. Should transfer legs be visible individually in the ledger, collapsed into one row, or user-selectable?
66. Should opening balances and balance corrections be separate concepts instead of transfer records?
67. Do you need account reconciliation against bank statements?

## G. Debt management

68. Which debt workflows are required: I borrowed money, I lent money, I repaid, I collected repayment, forgiveness, write-off, interest?
69. Should debt activity be managed through debt accounts, dedicated debt records, or both?
70. Is debt forgiveness genuinely needed, or can it be represented by a simple balance adjustment with a reason?
71. Do you need due dates, instalments, interest, minimum payments, reminders, or creditor details?
72. Can one person have multiple separate debts?
73. Should debt balances appear in net worth and reports? Exactly how?
74. Should debt settlement without cash movement be supported?
75. Should ordinary income/expense entry ever target a debt account?

## H. Advance and shared-expense management

76. Is the advance feature essential, useful but overbuilt, or not needed?
77. Is the desired mental model closer to “someone owes me” or to a Splitwise-style shared bill?
78. Must both directions remain: `I advanced others` and `others advanced me`?
79. Must an advance case include your own share?
80. Do you really need multiple participants in one case?
81. Do you really need multiple payment-source accounts in one case?
82. Do you need participants to be linked to persistent debt accounts?
83. Do you need partial repayments?
84. Do repayments need a different currency from the original case?
85. If currencies differ, should the user enter the normalized amount manually or should the app save an exchange rate?
86. Do you need mutual debt offset?
87. Do you need manual cross-currency settlement?
88. Do you need repayment records without actual cash movement?
89. Must users be able to change direction, currency, participants, payment legs, and repayments after creation?
90. Would a simpler rule—delete/reverse and recreate complex cases—be acceptable?
91. Should an advance appear as one summary row or expose every underlying ledger entry?
92. Should advance cases affect expense reports on the purchase date, repayment date, or differently by direction?
93. What should happen when repayments exceed the amount owed?
94. What should happen when a participant is removed after partial repayment?
95. Which existing advance behaviours are definitely not what you expected?

## I. Refunds, rebates, and reversals

96. Do you need a dedicated refund workflow?
97. Must a refund link to an original expense?
98. Should an unlinked refund be allowed?
99. Should refunds reduce expense rather than count as income?
100. Can refunds be partial?
101. Can refunds exceed the remaining original expense, and how should the excess be classified?
102. Can a refund go to a different account or currency from the original expense?
103. Do you genuinely need refunds routed through another person's debt account?
104. Would a simpler “negative expense linked to original transaction” model be enough?
105. Should reversing an incorrect transaction be different from recording a real merchant refund?

## J. Recurring entries and shortcuts

106. Should recurring rules create transactions automatically, or create pending occurrences for confirmation?
107. What should happen when the app has not opened for several months?
108. Should missed recurring entries be generated individually, summarized, skipped, or reviewed?
109. Do recurring rules need end dates, weekday rules, month-end handling, or variable amounts?
110. Are quick-entry shortcuts still useful?
111. Should shortcuts create immediately, show confirmation, or open a prefilled editor?
112. Should shortcuts support transfers, debt, and advances, or only income/expense?
113. Should the app learn recent/frequent entries instead of requiring manually managed shortcuts?

## K. Budgets and alerts

114. Are budgets a core requirement or optional feature?
115. Should budgets be monthly only?
116. Should budgets be by category, tag, account, or total spending?
117. Which carry-over modes are actually wanted, if any?
118. Should refunds restore available budget?
119. Should advance expenses consume budget on the expense date?
120. Should budget history be permanently stored or recalculated from transactions?
121. Do you need spending forecasts?
122. Do you need AI-generated budget suggestions?
123. Where should overspending alerts appear: in-app only, notification, widget, or nowhere?
124. Should users be able to disable all budget features cleanly?

## L. Reports and financial summaries

125. Which reports do you actually use: category spending, tags, income, cash flow, net worth, account balance history, debt/advance summary, budget variance?
126. Should the home dashboard and report screens use exactly the same calculation engine?
127. Should transfers, debt settlements, forgiveness, refunds, and asset adjustments be excluded from ordinary income/expense totals?
128. Should report values show original currencies, estimated main-currency values, or both?
129. Is using today's exchange rate for old transactions acceptable?
130. Do you need trend charts across months or years?
131. Do you need drill-down from totals to exact transactions?
132. Should tags duplicate a transaction into multiple tag totals or allocate the amount among tags?
133. Should advance outstanding balances be filtered by case creation date or by current outstanding state?
134. Which current dashboard or report numbers do you believe are wrong?
135. What single summary should appear when the app opens?

## M. AI receipt scanning

136. Is AI receipt scanning important, experimental, or unwanted?
137. Should Gemini remain the provider?
138. Is requiring users to supply their own API key acceptable?
139. Which fields must scanning extract?
140. Must every AI result be reviewed before saving?
141. Should receipt images ever leave the device without a clear confirmation?
142. Should AI functionality be removable without affecting the rest of the app?
143. Is “AI Accounting” still the right product name if AI scanning is optional?

## N. Backup, restore, export, and sync

144. Which backup methods are required: local JSON, Files app, WebDAV, iCloud Drive, automatic device backup?
145. Is WebDAV genuinely used, or was it added speculatively?
146. Must backups be encrypted?
147. Should encryption use a user passphrase, Keychain-held key, or both?
148. Do you need automatic backups? When should they run?
149. How many backup versions should be retained?
150. Do you need both merge import and destructive replace import?
151. If merge import finds the same UUID with different content, what should happen?
152. Should restore always show a preview with counts and balance impact?
153. Is CSV export needed? Is CSV import needed?
154. Are attached receipt images included in backups?
155. Should backup compatibility across iOS and Android remain a hard requirement?
156. Would you rather have reliable iOS-only backup than fragile cross-platform compatibility?

## O. Navigation and interaction design

157. What should the default tab be?
158. Which current tabs should remain: overview, ledger, reports, accounts, settings?
159. Is a separate overview/home tab useful or redundant?
160. Should the global floating add button remain?
161. What are the three most common add actions that should be one tap away?
162. Should complex debt/advance operations be hidden under secondary menus?
163. Is the first-launch user guide useful, too long, or unwanted?
164. Should date filters be shared across home, ledger, and reports, or independent?
165. Should filter controls be pinned or scroll with content?
166. Which screens currently feel most confusing or crowded?
167. Which terminology is unclear: debt, advance, repayment, settlement, transfer, account, balance, net worth, refund?
168. Should destructive edits favour strict blocking or convenient editing with undo?
169. Do you prefer Apple-native plain UI or a more custom visual design?
170. Are accessibility, Dynamic Type, VoiceOver, and reduced-motion support requirements?

## P. Localisation and naming

171. Which languages must be maintained now?
172. Should English remain British English?
173. Is Japanese genuinely required?
174. Should untranslated strings block releases?
175. Should financial terminology be Hong Kong Traditional Chinese specifically?
176. Should the repository and Xcode product be renamed from `AI 記帳` / `ai-accounting-ios`?
177. What should the final user-facing app name be?

## Q. Performance targets

178. What is the expected maximum number of transactions after several years?
179. What is the expected maximum number of accounts, tags, categories, and advance cases?
180. What launch time feels acceptable on your oldest supported device?
181. What ledger scrolling behaviour counts as acceptable?
182. How quickly should search results update while typing?
183. Is it acceptable to require date filters for very large histories?
184. Should reports calculate instantly, cache results, or calculate in the background?
185. Should account balances be stored/cached or always derived from transactions?
186. Have you observed overheating, memory warnings, freezes, or only general slowness?
187. Which exact actions currently feel slowest?

## R. Privacy and security

188. What personal data will the app store besides financial records?
189. Is biometric/App Lock required?
190. Should sensitive values be hidden in the app switcher or screenshots?
191. Must all data remain local unless the user explicitly invokes backup or AI scanning?
192. Should logs contain transaction amounts, notes, IDs, or none of these in production?
193. Should analytics/crash reporting be allowed?
194. Is secure deletion a requirement?
195. What threat are you most concerned about: accidental loss, another person opening the phone, cloud exposure, corrupted migration, or malicious import?

## S. Reliability, testing, and release process

196. Which is more important: preserving all existing features or reaching a smaller stable product quickly?
197. Should new feature work stop until critical correctness and performance problems are resolved?
198. Which workflows must have automated end-to-end tests?
199. Which data migrations must be tested using real anonymized store copies?
200. Should CI continue building Android on every shared change?
201. Should performance regression tests have explicit transaction-count fixtures and time limits?
202. What conditions should block a release?
203. Do you want formal versioned releases, TestFlight builds, or direct personal-device builds?
204. How frequently do you expect to ship changes?
205. Who besides you will test releases?

## T. Current defects and unwanted behaviour

206. List the five bugs that currently cause the most harm.
207. For each, what exact steps reproduce it?
208. Which bugs can alter balances or lose data?
209. Which bugs are visual only?
210. Which screens or actions crash?
211. Which calculations have produced known wrong numbers? Include examples if possible.
212. Which operations are unexpectedly slow? Include approximate data size and device.
213. Which current features do you never use?
214. Which current features do you actively want removed?
215. Which behaviours were implemented differently from what you originally described?
216. Are there generated/agent-created features that you never approved?
217. Are there duplicated screens or multiple ways to do the same task?
218. What part of the codebase are you most afraid to change?

## U. Final prioritisation and trade-offs

219. Name the five features that must survive any simplification.
220. Name the five features most suitable for removal or indefinite freezing.
221. Rank these priorities: data correctness, data safety, speed, simple UX, feature count, Android parity, backward compatibility, visual polish.
222. Would you prefer a stable iOS app with 60% of current features or the current feature set with ongoing complexity?
223. Which one complicated feature is worth keeping even if it increases maintenance cost?
224. Which compatibility promise are you willing to break?
225. What should be completed in the first stabilisation milestone?
226. What should explicitly be deferred until after stabilisation?
227. What objective evidence would prove that the cleanup succeeded?
228. What would make you decide that a clean rewrite is better than incremental refactoring?
229. Is there a deadline or event driving this work?
230. After answering everything above, describe the ideal app in five sentences without referring to the current implementation.

---

## Decision record

To be completed after the questionnaire is answered.

### Product statement

TBD

### Primary user and workflow

TBD

### Must keep

TBD

### Simplify

TBD

### Remove or freeze

TBD

### Data compatibility promise

TBD

### Platform decision

TBD

### Performance targets

TBD

### Stabilisation milestone

TBD

### Deferred work

TBD
