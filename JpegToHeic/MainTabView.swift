import SwiftUI

/// 三功能主界面：格式转换（JPEG→HEIC）+ 调色盘移植（含实况）+ 元数据修改
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
            ExifEditView()
                .tabItem {
                    Label("元数据", systemImage: "info.circle")
                }
        }
    }
}
