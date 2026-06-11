import SwiftUI
import SwiftData

struct EditTagView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var tag: Tag
    
    @State private var name: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("標籤名稱") {
                    TextField("例如: 旅行、報銷", text: $name)
                }
            }
            .standardKeyboardBehavior()
            .navigationTitle("編輯標籤")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        tag.name = name
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = tag.name
            }
        }
        .presentationDetents([.medium])
    }
}
