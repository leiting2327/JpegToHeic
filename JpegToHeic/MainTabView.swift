import SwiftUI

/// 双功能主界面：格式转换（JPEG→HEIC）+ 调色盘移植（给 HEIC 加摄影风格）
struct MainTabView: View {
    var body: some View {
        TabView {
            ContentView()
                .tabItem {
                    Label("格式转换", systemImage: "arrow.left.arrow.right")
                }
            StylePortView()
                .tabItem {
                    Label("调色盘", systemImage: "paintpalette")
                }
        }
    }
}
