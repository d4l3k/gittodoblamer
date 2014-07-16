require 'bundler'
Bundler.require

require 'json'

$redis = Redis.new

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
  def group todos
    todos.sort do |a, b|
      a['line'] <=> b['line']
    end.group_by do |obj|
      obj['filename']
    end
  end
  def all
    todos = []
    $redis.keys("blamer:repo:*").each do |repo|
      $redis.zrange(repo, 0, -1).each do |obj|
        todos.push(JSON.parse(obj))
      end
    end
    todos
  end
  def top_offenders
    off = all.group_by do |obj|
      obj['committer']
    end.map do |a, b|
      { label: a, value: b.length}
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
      tag = "blamer:#{request.path}"
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
    $redis.keys("blamer:repo:*").map do |repo|
      repo.split(':').last
    end
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

get '/repo/:project' do
  cache do
    project = params[:project].downcase
    todos = $redis.zrange("blamer:repo:#{project}", 0, -1).map do |obj|
      JSON.parse(obj)
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
    todos = []
    $redis.keys("blamer:repo:*").each do |repo|
      todos += $redis.zrange(repo, 0, -1).map do |obj|
        JSON.parse(obj)
      end
    end
    todos = todos.select do |obj|
      obj['committer-mail'] == "<#{email}>"
    end
    count = todos.length
    name = (todos.first || {})['committer']
    todos = group todos
    erb :project, locals: { title: "#{name} &lt;#{email}&gt;", groups: todos, todos: count }
  end
end
