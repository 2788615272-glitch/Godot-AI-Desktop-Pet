extends Node
class_name APIConnector

signal api_replied(response_text: String)
signal api_failed(error_code: int)

var http_request: HTTPRequest

func _ready():
	http_request = HTTPRequest.new()
	# 🚨 加在这里！因为这个文件里才有 http_request 这个变量
	http_request.set_http_proxy("127.0.0.1", 10090)
	http_request.set_https_proxy("127.0.0.1", 10090)
	add_child(http_request)
	http_request.request_completed.connect(_on_request_completed)

# ==========================================
# 路线零：硅基流动 (保留 DeepSeek 免费兜底)
# ==========================================
func send_to_siliconflow(prompt: String, base64_img: String, api_key: String):
	var payload = {
		"model": "deepseek-ai/deepseek-vl2", 
		"messages": [{"role": "user", "content": [
			{"type": "text", "text": prompt},
			{"type": "image_url", "image_url": {"url": "data:image/jpeg;base64," + base64_img}}
		]}],
		"max_tokens": 150,
		"temperature": 0.2
	}
	var headers = ["Content-Type: application/json", "Authorization: Bearer " + api_key]
	http_request.cancel_request()
	http_request.request("https://api.siliconflow.cn/v1/chat/completions", headers, HTTPClient.METHOD_POST, JSON.stringify(payload))

func send_text_to_siliconflow(prompt: String, api_key: String):
	var payload = {
		"model": "deepseek-ai/deepseek-vl2",
		"messages": [{"role": "user", "content": [
			{"type": "text", "text": prompt}
		]}],
		"max_tokens": 150,
		"temperature": 0.8
	}
	var headers = ["Content-Type: application/json", "Authorization: Bearer " + api_key]
	http_request.cancel_request()
	http_request.request("https://api.siliconflow.cn/v1/chat/completions", headers, HTTPClient.METHOD_POST, JSON.stringify(payload))

# ==========================================
# 路线一：Google Gemini 1.5 Flash (高智商降维打击)
# ==========================================
func send_to_gemini(prompt: String, base64_img: String, api_key: String):
	var payload = {
		"contents": [{
			"parts": [
				{"text": prompt},
				{
					"inline_data": {
						"mime_type": "image/jpeg",
						"data": base64_img
					}
				}
			]
		}],
		"generationConfig": {
			"temperature": 0.2
		}
	}
	var headers = ["Content-Type: application/json"]
	var url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=" + api_key
	http_request.cancel_request()
	http_request.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))

# ==========================================
# 终极接收站：自动兼容不同格式的返回值
# ==========================================
func _on_request_completed(_result, response_code, _headers, body):
	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		if response:
			var raw_output = ""
			
			# 1. 兼容 OpenAI/硅基流动/豆包 的标准格式
			if response.has("choices"):
				raw_output = response["choices"][0]["message"]["content"].strip_edges()
				
			# 2. 兼容 Google Gemini 的专属格式
			elif response.has("candidates"):
				raw_output = response["candidates"][0]["content"]["parts"][0]["text"].strip_edges()
				
			if raw_output != "":
				api_replied.emit(raw_output)
			else:
				api_failed.emit(response_code)
		else:
			api_failed.emit(response_code)
	else:
		print("【API_Connector 报错】状态码: ", response_code, " 内容: ", body.get_string_from_utf8())
		api_failed.emit(response_code)
