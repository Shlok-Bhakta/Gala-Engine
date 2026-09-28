import Foundation
import SwiftUI

private struct Todo: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var isDone = false
}

private struct TodoListView: View {
    @State private var todos: [Todo] = []
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    TextField("New task", text: $draft)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                        .onSubmit(addTodo)
                    Button("Add", action: addTodo)
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding()

                List {
                    ForEach($todos) { $todo in
                        Button {
                            todo.isDone.toggle()
                        } label: {
                            HStack {
                                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(todo.isDone ? .green : .secondary)
                                Text(todo.title)
                                    .strikethrough(todo.isDone)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { todos.remove(atOffsets: $0) }
                }
                .overlay {
                    if todos.isEmpty {
                        ContentUnavailableView("No tasks yet", systemImage: "checklist")
                    }
                }
            }
            .navigationTitle("To Do")
            .onAppear(perform: loadTodos)
            .onChange(of: todos) { _, newValue in
                if let data = try? JSONEncoder().encode(newValue) {
                    UserDefaults.standard.set(data, forKey: "todos")
                }
            }
        }
    }

    private func addTodo() {
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        todos.append(Todo(title: title))
        draft = ""
    }

    private func loadTodos() {
        guard let data = UserDefaults.standard.data(forKey: "todos"),
              let saved = try? JSONDecoder().decode([Todo].self, from: data) else { return }
        todos = saved
    }
}

@main
struct SwiftTodoApp: App {
    var body: some Scene {
        WindowGroup {
            TodoListView()
        }
    }
}
