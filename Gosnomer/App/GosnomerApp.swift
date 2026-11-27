import SwiftUI

@main
struct GosnomerApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() { AppSettings.register() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task { await model.start() }
                .onChange(of: scenePhase) { _, p in
                    // вернулись в приложение (например, из Telegram) — обновляем баланс
                    if p == .active, model.phase == .ready || model.phase == .group { Task { await model.refresh() } }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            switch model.phase {
            case .loading:
                LaunchView()
            case .login:
                LoginView()
            case .group:
                GroupGateView()
            case .ready:
                MainTabs()
            case .failed(let msg):
                FailedView(message: msg)
            }
        }
        .animation(.smooth, value: model.phase)
        .overlay(alignment: .top) {
            if let t = model.toast {
                Text(t)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18).padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 8).padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onTapGesture { withAnimation(.snappy) { model.toast = nil } }
            }
        }
        .animation(.snappy, value: model.toast)
        .alert("Госномер", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button("Понятно", role: .cancel) {}
        } message: {
            Text(model.alert ?? "")
        }
    }
}

struct MainTabs: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        TabView(selection: $model.tab) {
            Tab("Крутка", systemImage: "dice.fill", value: AppTab.spin) {
                SpinView()
            }
            Tab("Коллекция", systemImage: "rectangle.stack.fill", value: AppTab.collection) {
                CollectionView()
            }
            Tab("Профиль", systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

struct LaunchView: View {
    var body: some View {
        ZStack {
            BrandBackground()
            VStack(spacing: 22) {
                PlateView(kind: "civil", parts: ["l": "ГНМ", "d": "777", "r": "77"])
                    .frame(width: 260)
                    .shadow(color: .black.opacity(0.25), radius: 18, y: 8)
                ProgressView().tint(.white)
            }
        }
    }
}

struct FailedView: View {
    @EnvironmentObject var model: AppModel
    let message: String
    var body: some View {
        ZStack {
            BrandBackground()
            VStack(spacing: 18) {
                Image(systemName: "wifi.exclamationmark").font(.system(size: 44)).foregroundStyle(.white)
                Text("Не удалось загрузить игру").font(.title3.bold()).foregroundStyle(.white)
                Text(message).font(.subheadline).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
                Button("Повторить") { Task { await model.start() } }
                    .buttonStyle(.glassProminent).controlSize(.large)
                Button("Выйти из аккаунта") { model.signedOut() }
                    .buttonStyle(.glass)
            }
            .padding(32)
        }
    }
}

/// Синий фон как у иконки игры
struct BrandBackground: View {
    var body: some View {
        RadialGradient(colors: [Color(red: 0.59, green: 0.80, blue: 1.0), Color(red: 0.08, green: 0.51, blue: 0.96)],
                       center: UnitPoint(x: 0.5, y: 0.35), startRadius: 20, endRadius: 620)
            .ignoresSafeArea()
    }
}
