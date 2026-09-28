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

    private let canvas = Color(red: 1.0, green: 0.53, blue: 0.25)
    private let forest = Color(red: 0.30, green: 0.13, blue: 0.15)
    private let coral = Color(red: 0.91, green: 0.24, blue: 0.12)

    private var completedCount: Int {
        todos.filter(\.isDone).count
    }

    private var completion: Double {
        Double(completedCount) / Double(max(todos.count, 1))
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("ORANGE MODE")
                                .font(.largeTitle.bold())
                                .foregroundStyle(.white)
                            Text("This is the new SwiftTodo build.")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer()
                        Image(systemName: "sun.max.fill")
                            .font(.title2)
                            .foregroundStyle(coral)
                            .frame(width: 48, height: 48)
                            .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("YOUR PROGRESS")
                                    .font(.caption2.bold())
                                    .tracking(1.3)
                                    .foregroundStyle(.white.opacity(0.72))
                                Text("\(completedCount) of \(todos.count) tasks finished")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                            Spacer()
                            Text("\(Int(completion * 100))%")
                                .font(.title2.bold())
                                .foregroundStyle(.white)
                        }
                        ProgressView(value: completion)
                            .tint(Color(red: 1.0, green: 0.85, blue: 0.48))
                            .accessibilityLabel("Task completion")
                            .accessibilityValue("\(completedCount) of \(todos.count) tasks")
                    }
                    .padding(20)
                    .background(forest, in: RoundedRectangle(cornerRadius: 22))

                    HStack(spacing: 12) {
                        TextField("What needs doing?", text: $draft)
                            .textInputAutocapitalization(.sentences)
                            .submitLabel(.done)
                            .onSubmit(addTodo)
                        Button(action: addTodo) {
                            Image(systemName: "plus")
                                .font(.headline)
                                .frame(width: 38, height: 38)
                                .background(forest, in: RoundedRectangle(cornerRadius: 11))
                                .foregroundStyle(.white)
                        }
                        .accessibilityLabel("Add task")
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(10)
                    .padding(.leading, 8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 17))
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 12)

                List {
                    ForEach($todos) { $todo in
                        Button {
                            todo.isDone.toggle()
                        } label: {
                            HStack {
                                Image(systemName: todo.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(todo.isDone ? forest : coral)
                                Text(todo.title)
                                    .strikethrough(todo.isDone)
                                    .foregroundStyle(.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.white)
                    }
                    .onDelete { todos.remove(atOffsets: $0) }
                }
                .scrollContentBackground(.hidden)
                .overlay {
                    if todos.isEmpty {
                        ContentUnavailableView("A clear slate", systemImage: "checklist", description: Text("Add a task above to get started."))
                    }
                }
            }
            .background(canvas.ignoresSafeArea())
            .navigationTitle("SwiftTodo · Build \(buildNumber)")
            .navigationBarTitleDisplayMode(.inline)
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
