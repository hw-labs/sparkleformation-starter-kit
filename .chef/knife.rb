knife[:cloudformation][:processing] = true
knife[:cloudformation][:credentials] = {
  :aws_access_key_id => ENV['AWS_ACCESS_KEY_ID'],
  :aws_secret_access_key => ENV['AWS_SECRET_ACCESS_KEY'],
  :aws_region => ENV.fetch('AWS_DEFAULT_REGION', 'us-east-1')
}
