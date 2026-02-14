import Foundation
import Darwin

/// Direct access to macOS memory statistics via mach APIs
class MemoryMonitor {
    static let shared = MemoryMonitor()

    private init() {}

    /// Get total physical memory
    var totalMemory: UInt64 {
        var size: size_t = MemoryLayout<UInt64>.size
        var result: UInt64 = 0
        sysctlbyname("hw.memsize", &result, &size, nil, 0)
        return result
    }

    /// Get current system memory statistics using mach APIs
    func getSystemMemory() -> SystemMemory {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        let pageSize = UInt64(vm_kernel_page_size)
        let total = totalMemory

        guard result == KERN_SUCCESS else {
            return SystemMemory(
                total: total,
                used: 0,
                free: total,
                wired: 0,
                active: 0,
                inactive: 0,
                compressed: 0
            )
        }

        let wired = UInt64(stats.wire_count) * pageSize
        let active = UInt64(stats.active_count) * pageSize
        let inactive = UInt64(stats.inactive_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let free = UInt64(stats.free_count) * pageSize

        // Used = wired + active + compressed (standard macOS calculation)
        let used = wired + active + compressed

        return SystemMemory(
            total: total,
            used: used,
            free: total - used,
            wired: wired,
            active: active,
            inactive: inactive,
            compressed: compressed
        )
    }

}
