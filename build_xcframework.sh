#!/bin/bash
# =============================================================================
# build_xcframework.sh
# 将 EPUBKit 及其依赖（AEXML、Zip/Minizip）打包为 EPUBKit.xcframework
# 依赖库源码内联到 EPUBKit，不对外暴露
# 支持并发编译各平台
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
BUILD_DIR="$PROJECT_DIR/build_xcframework_tmp"
OUTPUT_DIR="$PROJECT_DIR/output"
XCFRAMEWORK_NAME="EPUBKit"
XCFRAMEWORK_OUTPUT="$OUTPUT_DIR/$XCFRAMEWORK_NAME.xcframework"

# 依赖源码路径（通过 swift package resolve 获取）
AEXML_SRC="$PROJECT_DIR/.build/checkouts/AEXML/Sources/AEXML"
ZIP_SRC="$PROJECT_DIR/.build/checkouts/Zip/Zip"

echo "============================================================"
echo "  Building $XCFRAMEWORK_NAME.xcframework"
echo "============================================================"

# -------------------------------------------------------
# Step 0: 确保依赖已下载
# -------------------------------------------------------
echo ""
echo "[Step 0] Resolving Swift Package dependencies..."
cd "$PROJECT_DIR"
swift package resolve
echo "  Done."

# -------------------------------------------------------
# Step 1: 准备临时构建目录
# -------------------------------------------------------
echo ""
echo "[Step 1] Preparing build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

MERGED_SOURCES="$BUILD_DIR/Sources/EPUBKit"
mkdir -p "$MERGED_SOURCES"

MINIZIP_DIR="$BUILD_DIR/Sources/Minizip"
mkdir -p "$MINIZIP_DIR/include"

echo "  Done."

# -------------------------------------------------------
# Step 2: 复制 EPUBKit 源码
# -------------------------------------------------------
echo ""
echo "[Step 2] Copying EPUBKit sources..."
cp -r "$PROJECT_DIR/Sources/EPUBKit/"* "$MERGED_SOURCES/"
echo "  Done."

# -------------------------------------------------------
# Step 3: 内联 AEXML 源码（将 public/open 改为 internal）
# -------------------------------------------------------
echo ""
echo "[Step 3] Inlining AEXML sources (making symbols internal)..."
mkdir -p "$MERGED_SOURCES/AEXML_Inlined"

for f in "$AEXML_SRC"/*.swift; do
    filename=$(basename "$f")
    sed \
        -e 's/^public enum /internal enum /g' \
        -e 's/^public struct /internal struct /g' \
        -e 's/^public class /internal class /g' \
        -e 's/^public protocol /internal protocol /g' \
        -e 's/^public extension /internal extension /g' \
        -e 's/^open class /internal class /g' \
        -e 's/^    public /    internal /g' \
        -e 's/^    open /    internal /g' \
        -e 's/^        public /        internal /g' \
        -e 's/^        open /        internal /g' \
        -e 's/^            public /            internal /g' \
        -e 's/^            open /            internal /g' \
        "$f" > "$MERGED_SOURCES/AEXML_Inlined/$filename"
done
echo "  Done."

# -------------------------------------------------------
# Step 4: 内联 Zip Swift 源码（将 public 改为 internal）
# -------------------------------------------------------
echo ""
echo "[Step 4] Inlining Zip Swift sources (making symbols internal)..."
mkdir -p "$MERGED_SOURCES/Zip_Inlined"

for f in "$ZIP_SRC"/*.swift; do
    filename=$(basename "$f")
    sed \
        -e 's/^public enum /internal enum /g' \
        -e 's/^public struct /internal struct /g' \
        -e 's/^public class /internal class /g' \
        -e 's/^public protocol /internal protocol /g' \
        -e 's/^public extension /internal extension /g' \
        -e 's/^open class /internal class /g' \
        -e 's/^    public /    internal /g' \
        -e 's/^    open /    internal /g' \
        -e 's/^        public /        internal /g' \
        -e 's/^        open /        internal /g' \
        -e 's/^            public /            internal /g' \
        -e 's/^            open /            internal /g' \
        "$f" > "$MERGED_SOURCES/Zip_Inlined/$filename"
done
echo "  Done."

# -------------------------------------------------------
# Step 5: 复制 Minizip C 源码
# -------------------------------------------------------
echo ""
echo "[Step 5] Copying Minizip C sources..."
cp "$ZIP_SRC/minizip/ioapi.c" "$MINIZIP_DIR/"
cp "$ZIP_SRC/minizip/unzip.c" "$MINIZIP_DIR/"
cp "$ZIP_SRC/minizip/zip.c" "$MINIZIP_DIR/"
cp "$ZIP_SRC/minizip/include/"*.h "$MINIZIP_DIR/include/"

cat > "$MINIZIP_DIR/include/module.modulemap" << 'EOF'
module Minizip [system][extern_c] {
    header "Minizip.h"
    link "z"
    export *
}
EOF
echo "  Done."

# -------------------------------------------------------
# Step 6: 修改 EPUBKit 源码（移除 import，修复内部类型暴露）
# -------------------------------------------------------
echo ""
echo "[Step 6] Patching EPUBKit sources..."

# 移除 import AEXML 和 import Zip
find "$MERGED_SOURCES" -name "*.swift" \
    -not -path "*/AEXML_Inlined/*" \
    -not -path "*/Zip_Inlined/*" | while read f; do
    sed -i '' \
        -e '/^import AEXML$/d' \
        -e '/^import Zip$/d' \
        "$f"
done

# EPUBParsable 改为 internal（内部实现细节）
PARSABLE_FILE="$MERGED_SOURCES/Protocols/EPUBParsable.swift"
[ -f "$PARSABLE_FILE" ] && sed -i '' \
    -e 's/^public protocol EPUBParsable/internal protocol EPUBParsable/g' \
    "$PARSABLE_FILE" && echo "  Patched: EPUBParsable -> internal"

# EPUBParser 中的 typealias 和 EPUBParsable 实现方法改为 internal
PARSER_FILE="$MERGED_SOURCES/Parser/EPUBParser.swift"
[ -f "$PARSER_FILE" ] && sed -i '' \
    -e 's/    public typealias XMLElement = AEXMLElement/    internal typealias XMLElement = AEXMLElement/g' \
    -e 's/    public func unzip(archiveAt/    internal func unzip(archiveAt/g' \
    -e 's/    public func getSpine(from/    internal func getSpine(from/g' \
    -e 's/    public func getMetadata(from/    internal func getMetadata(from/g' \
    -e 's/    public func getManifest(from/    internal func getManifest(from/g' \
    -e 's/    public func getTableOfContents(from/    internal func getTableOfContents(from/g' \
    "$PARSER_FILE" && echo "  Patched: EPUBParser typealias + methods -> internal"

# EPUBParserProtocol 移除 EPUBParsable 约束
PROTOCOL_FILE="$MERGED_SOURCES/Protocols/EPUBParserProtocol.swift"
[ -f "$PROTOCOL_FILE" ] && sed -i '' \
    -e 's/^public protocol EPUBParserProtocol where Self: EPUBParsable/public protocol EPUBParserProtocol/g' \
    "$PROTOCOL_FILE" && echo "  Patched: EPUBParserProtocol removed EPUBParsable constraint"

echo "  Done."

# -------------------------------------------------------
# Step 7: 创建合并后的 Package.swift
# -------------------------------------------------------
echo ""
echo "[Step 7] Creating merged Package.swift..."

cat > "$BUILD_DIR/Package.swift" << 'PKGEOF'
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EPUBKit",
    platforms: [
        .macOS(.v10_13),
        .iOS(.v12),
        .tvOS(.v12)
    ],
    products: [
        .library(name: "EPUBKit", targets: ["EPUBKit"]),
    ],
    targets: [
        .target(
            name: "Minizip",
            path: "Sources/Minizip",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include")
            ],
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .target(
            name: "EPUBKit",
            dependencies: ["Minizip"],
            path: "Sources/EPUBKit"
        ),
    ]
)
PKGEOF
echo "  Done."

# -------------------------------------------------------
# Step 8: 验证合并后的包能编译
# -------------------------------------------------------
echo ""
echo "[Step 8] Verifying merged package builds..."
cd "$BUILD_DIR"
if swift build -c release 2>&1 | tee /tmp/epub_build_verify.log | grep -q "^.*error:"; then
    echo "  BUILD ERRORS:"
    grep "error:" /tmp/epub_build_verify.log | head -20
    exit 1
fi
echo "  Build verification passed."

# -------------------------------------------------------
# Step 9: 并发构建各平台静态库
# -------------------------------------------------------
echo ""
echo "[Step 9] Building static libraries concurrently for all platforms..."

cd "$BUILD_DIR"
LIBS_DIR="$BUILD_DIR/libs"
mkdir -p "$LIBS_DIR"

# 平台定义：名称|xcodebuild destination|derivedData目录|产物子目录|SDK检测关键字
declare -a PLATFORMS=(
    "iOS_device|generic/platform=iOS|$LIBS_DIR/dd_ios|Release-iphoneos|iphoneos"
    "iOS_Simulator|generic/platform=iOS Simulator|$LIBS_DIR/dd_iossim|Release-iphonesimulator|iphonesimulator"
    "macOS|generic/platform=macOS|$LIBS_DIR/dd_macos|Release|macosx"
    "tvOS_device|generic/platform=tvOS|$LIBS_DIR/dd_tvos|Release-appletvos|appletvos"
    "tvOS_Simulator|generic/platform=tvOS Simulator|$LIBS_DIR/dd_tvossim|Release-appletvsimulator|appletvsimulator"
)

# 并发构建函数
build_platform_async() {
    local name="$1"
    local destination="$2"
    local dd_path="$3"
    local products_subdir="$4"
    local sdk_key="$5"
    local log_file="/tmp/epub_build_${name}.log"
    local status_file="/tmp/epub_build_${name}.status"

    # 检查 SDK 是否安装
    if ! xcodebuild -showsdks 2>/dev/null | grep -q "$sdk_key"; then
        echo "SKIPPED:SDK $sdk_key not installed" > "$status_file"
        return 0
    fi

    xcodebuild build \
        -scheme EPUBKit \
        -destination "$destination" \
        -derivedDataPath "$dd_path" \
        -configuration Release \
        BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
        MACH_O_TYPE=staticlib \
        SWIFT_PACKAGE_NAME=EPUBKit \
        > "$log_file" 2>&1
    local exit_code=$?

    if [ $exit_code -eq 0 ]; then
        local products_dir="$dd_path/Build/Products/$products_subdir"
        if [ -f "$products_dir/EPUBKit.o" ]; then
            echo "SUCCESS:$products_dir" > "$status_file"
        else
            echo "FAILED:products not found at $products_dir" > "$status_file"
        fi
    else
        echo "FAILED:exit_code=$exit_code" > "$status_file"
    fi
}

# 清理旧的状态文件
for platform_info in "${PLATFORMS[@]}"; do
    IFS='|' read -r name destination dd_path products_subdir sdk_key <<< "$platform_info"
    rm -f "/tmp/epub_build_${name}.status"
done

# 启动所有平台的并发构建
declare -a PIDS=()
for platform_info in "${PLATFORMS[@]}"; do
    IFS='|' read -r name destination dd_path products_subdir sdk_key <<< "$platform_info"
    echo "  Starting: $name..."
    build_platform_async "$name" "$destination" "$dd_path" "$products_subdir" "$sdk_key" &
    PIDS+=($!)
done

# 等待所有构建完成
echo ""
echo "  Waiting for all builds to complete..."
TOTAL=${#PIDS[@]}
COMPLETED=0
for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
    COMPLETED=$((COMPLETED + 1))
    echo "  Progress: $COMPLETED/$TOTAL builds finished"
done

echo ""
echo "  Build results:"
for platform_info in "${PLATFORMS[@]}"; do
    IFS='|' read -r name destination dd_path products_subdir sdk_key <<< "$platform_info"
    status_file="/tmp/epub_build_${name}.status"
    if [ -f "$status_file" ]; then
        status=$(cat "$status_file")
        case "${status%%:*}" in
            SUCCESS) echo "    ✓ $name" ;;
            SKIPPED) echo "    - $name (skipped: ${status#*:})" ;;
            FAILED)
                echo "    ✗ $name (FAILED: ${status#*:})"
                grep "error:" "/tmp/epub_build_${name}.log" 2>/dev/null | head -3 | sed 's/^/        /'
                ;;
        esac
    fi
done

# -------------------------------------------------------
# Step 10: 将各平台 .o 文件合并为 .a 静态库
# -------------------------------------------------------
echo ""
echo "[Step 10] Creating static libraries (.a) from object files..."

STATIC_LIBS_DIR="$BUILD_DIR/static_libs"
mkdir -p "$STATIC_LIBS_DIR"

for platform_info in "${PLATFORMS[@]}"; do
    IFS='|' read -r name destination dd_path products_subdir sdk_key <<< "$platform_info"
    status_file="/tmp/epub_build_${name}.status"
    [ -f "$status_file" ] || continue
    status=$(cat "$status_file")
    [ "${status%%:*}" = "SUCCESS" ] || continue

    products_dir="${status#*:}"
    lib_dir="$STATIC_LIBS_DIR/$name"
    mkdir -p "$lib_dir"

    # 合并 EPUBKit.o 和 Minizip.o 为单个静态库
    libtool -static \
        "$products_dir/EPUBKit.o" \
        "$products_dir/Minizip.o" \
        -o "$lib_dir/EPUBKit.a"

    # 复制 swiftmodule 文件到专用的 headers 目录
    # （-headers 目录的内容会被 xcodebuild -create-xcframework 复制到 xcframework 的 Headers/ 中）
    if [ -d "$products_dir/EPUBKit.swiftmodule" ]; then
        headers_dir="$lib_dir/Headers"
        mkdir -p "$headers_dir/EPUBKit.swiftmodule"
        # 只复制文件，不复制子目录（Project/ 目录包含私有信息）
        find "$products_dir/EPUBKit.swiftmodule" -maxdepth 1 -type f | while read f; do
            cp "$f" "$headers_dir/EPUBKit.swiftmodule/"
        done
    fi

    echo "  Created: $name/EPUBKit.a ($(du -sh "$lib_dir/EPUBKit.a" | cut -f1))"
done

# -------------------------------------------------------
# Step 11: 创建 xcframework
# -------------------------------------------------------
echo ""
echo "[Step 11] Creating xcframework..."

rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

XCFRAMEWORK_ARGS=""
for platform_info in "${PLATFORMS[@]}"; do
    IFS='|' read -r name destination dd_path products_subdir sdk_key <<< "$platform_info"
    lib_dir="$STATIC_LIBS_DIR/$name"
    lib_file="$lib_dir/EPUBKit.a"
    headers_dir="$lib_dir/Headers"

    if [ -f "$lib_file" ]; then
        XCFRAMEWORK_ARGS="$XCFRAMEWORK_ARGS -library $lib_file"
        # 如果有 headers 目录（包含 swiftmodule），添加 -headers 参数
        if [ -d "$headers_dir" ]; then
            XCFRAMEWORK_ARGS="$XCFRAMEWORK_ARGS -headers $headers_dir"
        fi
        echo "  Adding: $name"
    fi
done

if [ -z "$XCFRAMEWORK_ARGS" ]; then
    echo "  ERROR: No libraries found!"
    exit 1
fi

xcodebuild -create-xcframework \
    $XCFRAMEWORK_ARGS \
    -output "$XCFRAMEWORK_OUTPUT"

echo ""
echo "============================================================"
echo "  SUCCESS!"
echo "  Output: $XCFRAMEWORK_OUTPUT"
echo "============================================================"
echo ""
echo "  Platforms included:"
ls "$XCFRAMEWORK_OUTPUT/"
echo ""
echo "  Size: $(du -sh "$XCFRAMEWORK_OUTPUT" | cut -f1)"
echo ""

# -------------------------------------------------------
# Step 12: 清理临时文件，只保留 EPUBKit.xcframework
# -------------------------------------------------------
echo ""
echo "[Step 12] Cleaning up temporary files..."
rm -rf "$BUILD_DIR"
echo "  Removed: $BUILD_DIR"
echo "  Done."
