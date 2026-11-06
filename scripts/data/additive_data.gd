class_name AdditiveData
extends Resource
## 饵料的附加物（交接文档 §5.1）：一份饵 = 两份基础材料 + 一份附加物。在 data/additives/ 下新建 .tres 即可添加。
## 附加物带一种气味（Aspect），按生物原有的偏好把上钩倾向往喜欢它的那边推、从讨厌它的那边拉开（BiteCalculator）。
## 不带气味的是基础款：用不完，什么都不特别招（设计对照文档第 8 条）。

@export var id: String
@export var display_name: String
@export_multiline var description: String
## 给饵料起名时用的字，例如溺死者的指甲 → "甲"（"甲·骨渣饵"）；基础款留空
@export var name_token: String
## 带的气味（Aspect 的 id）；留空 = 不改变上钩倾向
@export var aspect := ""
## 气味有多冲：生物的权重 × e^(强度 × 它对这种气味的偏好)。偏好 1 时强度 1.2 约是 ×3.3，偏好 −0.8 时约是 ×0.38
@export var strength := 1.2
## 用不完（基础款）
@export var unlimited := false
## 图标（小静物）；没有时用气味印章代替
@export var icon: Texture2D
