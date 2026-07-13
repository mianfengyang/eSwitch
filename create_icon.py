#!/usr/bin/env python3
from PIL import Image, ImageDraw, ImageFont
import os

def create_icon():
    # 创建图标目录
    iconset_path = "/Users/mifyang/project/cubetab/icon.iconset"
    os.makedirs(iconset_path, exist_ok=True)
    
    # 图标尺寸列表
    sizes = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    
    for size, filename in sizes:
        # 创建画布
        img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(img)
        
        # 计算缩放比例
        scale = size / 512.0
        
        # 绘制圆角矩形背景
        margin = int(20 * scale)
        corner_radius = int(100 * scale)
        draw.rounded_rectangle(
            [margin, margin, size - margin, size - margin],
            radius=corner_radius,
            fill=(50, 50, 50, 255)
        )
        
        # 绘制立方体
        center_x, center_y = size // 2, size // 2
        cube_size = int(180 * scale)
        
        # 立方体的顶点
        front_top_left = (center_x - cube_size//2, center_y - cube_size//2)
        front_top_right = (center_x + cube_size//2, center_y - cube_size//2)
        front_bottom_left = (center_x - cube_size//2, center_y + cube_size//2)
        front_bottom_right = (center_x + cube_size//2, center_y + cube_size//2)
        
        # 3D 效果偏移
        offset = int(40 * scale)
        
        # 绘制侧面（右）
        draw.polygon([
            front_top_right,
            (front_top_right[0] + offset, front_top_right[1] - offset),
            (front_bottom_right[0] + offset, front_bottom_right[1] - offset),
            front_bottom_right
        ], fill=(100, 100, 100, 255))
        
        # 绘制顶面
        draw.polygon([
            front_top_left,
            front_top_right,
            (front_top_right[0] + offset, front_top_right[1] - offset),
            (front_top_left[0] + offset, front_top_left[1] - offset)
        ], fill=(120, 120, 120, 255))
        
        # 绘制正面
        draw.rectangle(
            [front_top_left, front_bottom_right],
            fill=(180, 180, 180, 255),
            outline=(255, 255, 255, 255),
            width=max(1, int(3 * scale))
        )
        
        # 绘制旋转箭头
        arrow_center = (center_x + int(10 * scale), center_y)
        arrow_size = int(50 * scale)
        
        # 箭头弧线
        draw.arc(
            [arrow_center[0] - arrow_size, arrow_center[1] - arrow_size,
             arrow_center[0] + arrow_size, arrow_center[1] + arrow_size],
            start=200, end=340,
            fill=(0, 200, 255, 255),
            width=max(2, int(6 * scale))
        )
        
        # 箭头头部
        arrow_tip_x = arrow_center[0] + int(arrow_size * 0.7)
        arrow_tip_y = arrow_center[1] - int(arrow_size * 0.7)
        arrow_head_size = int(15 * scale)
        
        draw.polygon([
            (arrow_tip_x + arrow_head_size, arrow_tip_y),
            (arrow_tip_x - arrow_head_size, arrow_tip_y - arrow_head_size),
            (arrow_tip_x - arrow_head_size, arrow_tip_y + arrow_head_size)
        ], fill=(0, 200, 255, 255))
        
        # 保存图标
        img.save(os.path.join(iconset_path, filename))
        print(f"Created {filename}")
    
    print("Icon set created successfully!")

if __name__ == "__main__":
    create_icon()
