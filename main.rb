require 'bundler'
Bundler.require

require 'json'

$redis = Redis.new

I18n.enforce_available_locales = true

configure do
  Compass.configuration do |config|
    config.project_path = File.dirname(__FILE__)
    config.sass_dir = 'views'
  end

  set :haml, { :format => :html5 }
  set :sass, Compass.sass_engine_options
  set :scss, Compass.sass_engine_options
end

helpers do
  include ActionView::Helpers::DateHelper
  def group todos
    todos.sort do |a, b|
      a['line'] <=> b['line']
    end.group_by do |obj|
      "#{obj['repo']}: #{obj['filename']}"
    end
  end
  def all
    todos = []
    $redis.keys("blamer:repo:*").each do |repo|
      $redis.zrange(repo, 0, -1).each do |obj|
        json = JSON.parse(obj)
        json['committer-time'] = Time.at(json['committer-time'].to_i)
        todos.push(json)
      end
    end
    todos
  end
  def top_offenders
    off = all.group_by do |obj|
      [obj['committer'], obj['committer-mail']]
    end.map do |a, b|
      { label: a[0], email: a[1], value: b.length}
    end.sort do |a, b|
      a[:value] <=> b[:value]
    end
    off.each_with_index do |obj, i|
      obj[:color] = "hsl(#{i * 360.0 / off.length},100%,50%)"
    end
    off
  end
  def cache time: 3600, &block
      if "development" == ENV["RACK_ENV"]
          return yield
      end
      tag = "blamer:url:#{request.path}"
      page = $redis.get(tag)
      if page
          etag Digest::SHA1.hexdigest(page)
          ttl = $redis.ttl(tag)
          response.header['redis-ttl'] = ttl.to_s
          response.header['redis'] = 'HIT'
      else
          page = yield
          etag Digest::SHA1.hexdigest(page)
          response.header['redis'] = 'MISS'
          $redis.setex(tag, time, page)
      end
      page
  end
  def repo_names
    names = $redis.keys("blamer:repo:*").map do |repo|
      { label: repo.split(':').last.capitalize, value: $redis.zcard(repo)}
    end.sort do |a, b|
      a[:value] <=> b[:value]
    end
    names.each_with_index do |obj, i|
      obj[:color] = "hsl(#{i * 360.0 / names.length},100%,50%)"
    end
    names
  end
  def shame count: 99
    {"" => all.sort do |a, b|
      a['committer-time'] <=> b['committer-time']
    end[0..count]}
  end
  def h(text)
    Rack::Utils.escape_html(text)
  end
end

get '/:file.css' do
  cache do
    sass params[:file].to_sym
  end
end

get '/' do
  cache do
    count = 0
    $redis.keys("blamer:repo:*").map do |repo|
      count += $redis.zcard(repo)
    end
    erb :index, locals: {title: "When were you actually going to do that?", todos: count, offenders: top_offenders}
  end
end

get '/age' do
  cache do
    sh = shame count: -1
    erb :project, locals: {title: "Wall of Shame", todos: sh[''].length, groups: sh}
  end
end

get '/repo/:project' do
  cache do
    project = params[:project].downcase
    todos = $redis.zrange("blamer:repo:#{project}", 0, -1).map do |obj|
      json = JSON.parse(obj)
      json['committer-time'] = Time.at(json['committer-time'].to_i)
      json
    end
    count = todos.length
    todos = group todos
    erb :project, locals: { title: project.capitalize, groups: todos, todos: count }
  end
end
get '/email/:email' do
  cache do
    email = params[:email]
    name = ""
    todos = all.select do |obj|
      obj['committer-mail'] == "<#{email}>"
    end
    count = todos.length
    name = (todos.first || {})['committer']
    todos = group todos
    erb :project, locals: { title: "#{name} &lt;#{email}&gt;", groups: todos, todos: count }
  end
end
