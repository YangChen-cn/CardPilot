import SwiftUI

struct RegionPicker: View {
    @Binding var region: String
    var body: some View {
        Picker("商户地区", selection: $region) {
            Text("未指定").tag("")
            Text("香港").tag("HK"); Text("中国内地").tag("CN"); Text("澳门").tag("MO")
            Text("其他地区").tag("other")
        }
    }
}
