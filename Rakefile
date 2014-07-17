task 'pry' do
  require 'bundler'
  Bundler.require
  require './main'
  binding.pry
end

task 'analyze' do
  require 'redis'
  require 'json'
  require 'pry'

  $redis = Redis.new
  ignore = %w{node_modules bower_components packages bower plugins target vendor}
  messages = []
  dirs = Dir.glob("../socrata/*")
  dirs.each do |dir|
    name = dir.split('/').last.downcase
    key = "blamer:repo:#{name}"
    if File.exists? "#{dir}/.git"
      puts "Processing #{name.capitalize}"
      files = `cd #{dir}; cgrep -rj16 --format="#f" --max-count=1 "TODO"`.split("\n")
      files = files.reject do |file|
        reject = false
        ignore.each do |i|
          if file.downcase.include? i
            reject = true
          end
        end
        reject
      end
      $redis.del key
      files.each do |file|
        puts " :: #{file}"
        blame = `cd #{dir}; git blame --line-porcelain #{file}`
        time = Time.now.to_i
        lines = []
        obj = {}
        blame.split("\n").each do |line|
          if line[0] != "\t"
            space = line.index(' ')
            if !space.nil?
              k = line[0...space]
              if k.length == 40
                parts = line.split(' ')
                obj['commit'] = parts[0]
                obj['char'] = parts[1].to_i
                obj['line'] = parts[2].to_i
              else
                v = line[space + 1..-1]
                obj[k] = v
              end
            elsif line == "boundary"
            else
              puts "WEIRD: #{file} #{line}"
            end
          else
            if line.downcase.include?('todo')
              obj['code'] = line[1..-1]
              obj['repo'] = name
              lines.push([time, JSON.dump(obj)])
            end
            obj = {}
          end
        end
        $redis.zadd(key, lines) unless lines.empty?
      end
    end
  end
end

task 'update' do
  require 'json'
  require 'pry'
  repos = []
  print "Enter password: "
  password = STDIN.noecho(&:gets)[0...-1]
  types = %w{private public}
  types.each do |type|
    resp = JSON.parse(`curl -u "d4l3k:#{password}" https://api.github.com/orgs/socrata/repos\?type\=#{type}`)
    repos += resp
  end
  repos.each_with_index do |repo, i|
    puts "Repo: #{repo['full_name']} (#{i+1}/#{repos.length})"
    if !File.exists?("../socrata/#{repo['name']}")
      system("cd ../socrata/; git clone git@github.com:#{repo['full_name']}.git")
    else
      system("cd ../socrata/#{repo['name']}; git checkout master; git pull")
    end
    puts "----"
  end
end

task 'cache:bust' do
  require 'redis'
  $redis = Redis.new
  $redis.keys("blamer:url:*").each do |url|
    $redis.del url
  end
end
