import SwiftUI
import SwiftData

struct TagsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Tag.name) private var tags: [Tag]
    
    @State private var showingAddTag = false
    @State private var newTagName = ""
    @State private var tagToEdit: Tag? // 用於控制編輯彈窗
    
    var body: some View {
        List {
            ForEach(tags) { tag in
                Text(tag.name)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle()) // 讓整行可點擊
                    .onTapGesture {
                        tagToEdit = tag
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            modelContext.delete(tag)
                        } label: {
                            Label("刪除", systemImage: "trash")
                        }
                        
                        Button {
                            tagToEdit = tag
                        } label: {
                            Label("編輯", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
            }
        }
        .navigationTitle("標籤管理")
        .standardKeyboardBehavior()
        .overlay {
            if tags.isEmpty {
                ContentUnavailableView("尚無標籤", systemImage: "tag", description: Text("標籤可幫助您更靈活地標記交易"))
            }
        }
        .toolbar {
            Button(action: { showingAddTag = true }) {
                Image(systemName: "plus")
            }
        }
        // 新增標籤 Alert
        .alert("新增標籤", isPresented: $showingAddTag) {
            TextField("標籤名稱", text: $newTagName)
            Button("取消", role: .cancel) {
                hideKeyboard()
                newTagName = ""
            }
            Button("儲存") {
                hideKeyboard()
                if !newTagName.isEmpty {
                    let tag = Tag(name: newTagName)
                    modelContext.insert(tag)
                    newTagName = ""
                }
            }
        }
        // 編輯標籤 Sheet
        .sheet(item: $tagToEdit) { tag in
            EditTagView(tag: tag) // 這裡呼叫剛剛修正的 EditTagView
        }
    }
}
