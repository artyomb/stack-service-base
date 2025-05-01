module PrometheusParser
  def self.parse_metrics(text)
    metrics = Hash.new { |h, k| h[k] = { series: [] } }

    series = ->(name, labels) do
      metrics[name][:series].find { _1[:labels] == labels } ||
        metrics[name][:series] << { labels: labels } and metrics[name][:series].last
    end

    text.each_line(chomp: true) do |l|
      case l
      when /\A#\s*HELP\s+(\S+)\s+(.+)/
        metrics[$1.to_sym][:help] = $2
      when /\A#\s*TYPE\s+(\S+)\s+(\S+)/
        metrics[$1.to_sym][:type] = $2.to_sym
      when /\A([^ {]+)(?:\{([^}]*)\})?\s+([0-9eE+\-\.]+)\z/
        name, lbls, val = $1.to_sym, $2, $3.to_f
        labels = lbls.to_s.split(',').to_h { |kv| k, v = kv.split('='); [k.to_sym, v.delete('"')] }

        case
        when name.to_s.end_with?('_bucket')
          base = name.to_s.sub(/_bucket\z/, '').to_sym
          le   = labels.delete(:le)
          (entry = series[base, labels])[:buckets] ||= {}
          entry[:buckets][le] = val
        when name.to_s =~ /(.*)_(sum|count)\z/
          base, field = Regexp.last_match(1).to_sym, Regexp.last_match(2).to_sym
          (series[base, labels])[field] = val
        when labels.key?(:quantile)                           # Summary quantile
          q = labels.delete(:quantile)
          (entry = series[name, labels])[:quantiles] ||= {}
          entry[:quantiles][q] = val
        else                                                  # Counter/Gauge sample
          metrics[name][:series] << { labels: labels, value: val }
        end
      end
    end

    metrics
  end
end

metrics_text = <<~METRICS
  # TYPE http_server_requests_total counter
  # HELP http_server_requests_total The total number of HTTP requests handled by the Rack application.
  http_server_requests_total{code="200",method="get",path="/"} 5.0
  http_server_requests_total{code="200",method="get",path="/metrics"} 18.0
  # TYPE http_server_request_duration_seconds histogram
  # HELP http_server_request_duration_seconds The HTTP response duration of the Rack application.
  http_server_request_duration_seconds_bucket{method="get",path="/",le="0.005"} 0.0
  http_server_request_duration_seconds_bucket{method="get",path="/",le="0.01"} 0.0
  http_server_request_duration_seconds_bucket{method="get",path="/",le="0.025"} 0.0
  http_server_request_duration_seconds_bucket{method="get",path="/",le="0.05"} 4.0
  http_server_request_duration_seconds_bucket{method="get",path="/",le="0.1"} 5.0
  http_server_request_duration_seconds_bucket{method="get",path="/",le="0.25"} 5.0
  http_server_request_duration_seconds_bucket{method="get",path="/",le="0.5"} 5.0
  http_server_request_duration_seconds_bucket{method="get",path="/",le="1"} 5.0
  http_server_request_duration_seconds_bucket{method="get",path="/",le="2.5"} 5.0
  http_server_request_duration_seconds_bucket{method="get",path="/",le="5"} 5.0
  http_server_request_duration_seconds_bucket{method="get",path="/",le="10"} 5.0
  http_server_request_duration_seconds_bucket{method="get",path="/",le="+Inf"} 5.0
  http_server_request_duration_seconds_sum{method="get",path="/"} 0.1885649065952748
  http_server_request_duration_seconds_count{method="get",path="/"} 5.0
  http_server_request_duration_seconds_bucket{method="get",path="/metrics",le="0.005"} 18.0
  http_server_request_duration_seconds_bucket{method="get",path="/metrics",le="0.01"} 18.0
  http_server_request_duration_seconds_bucket{method="get",path="/metrics",le="0.025"} 18.0
  http_server_request_duration_seconds_bucket{method="get",path="/metrics",le="0.05"} 18.0
  http_server_request_duration_seconds_bucket{method="get",path="/metrics",le="0.1"} 18.0
  http_server_request_duration_seconds_bucket{method="get",path="/metrics",le="0.25"} 18.0
  http_server_request_duration_seconds_bucket{method="get",path="/metrics",le="0.5"} 18.0
  http_server_request_duration_seconds_bucket{method="get",path="/metrics",le="1"} 18.0
  http_server_request_duration_seconds_bucket{method="get",path="/metrics",le="2.5"} 18.0
  http_server_request_duration_seconds_bucket{method="get",path="/metrics",le="5"} 18.0
  http_server_request_duration_seconds_bucket{method="get",path="/metrics",le="10"} 18.0
  http_server_request_duration_seconds_bucket{method="get",path="/metrics",le="+Inf"} 18.0
  http_server_request_duration_seconds_sum{method="get",path="/metrics"} 0.012181486235931516
  http_server_request_duration_seconds_count{method="get",path="/metrics"} 18.0
  # TYPE http_server_exceptions_total counter
  # HELP http_server_exceptions_total The total number of exceptions raised by the Rack application.
METRICS

metrics = PrometheusParser::parse_metrics metrics_text

# Print the parsed metrics
metrics.each do |name, data|
  puts "Metric: #{name}"
  puts "Description: #{data[:help]}"
  puts "Type: #{data[:type]}"
  data[:series].each do |series|
    puts "    #{series} "
  end
  puts
end