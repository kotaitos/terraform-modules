variable "environment" {
  description = "環境設定。他のモジュールとインターフェースを揃えるため同じ形を受け取る。"
  type = object({
    project_id   = string
    project_name = optional(string)
    region       = optional(string)
    stack_name   = optional(string)
  })
}

# TODO: モジュール名と同じ名前の設定オブジェクトを、実際の設定項目に置き換える。
variable "__MODULE_SNAKE__" {
  description = "__MODULE_NAME__ の設定。"
  type = object({
    services           = list(string)
    disable_on_destroy = optional(bool, false)
  })

  validation {
    condition     = length(var.__MODULE_SNAKE__.services) > 0
    error_message = "__MODULE_SNAKE__.services は 1 つ以上指定してください。"
  }

  validation {
    condition     = length(var.__MODULE_SNAKE__.services) == length(distinct(var.__MODULE_SNAKE__.services))
    error_message = "__MODULE_SNAKE__.services に重複があります。重複を取り除いてください。"
  }
}
