# Erik Kastner 2008-02-16 small blog engine with XMLRPC, hAtom and S3 upload (through xlmrpc) support
require 'rubygems'
require 'sinatra'
require 'xmlrpc/marshal'
require 'active_record'
require 'aws/s3'

BUCKET = "sinatra-data.metaatem.net"
ActiveRecord::Base.establish_connection(:adapter => "sqlite3", :database => "sin.db")

begin
  ActiveRecord::Schema.define do
    create_table :posts do |t|
      t.string :title
      t.string :author
      t.text :description
      t.timestamps
    end
  end
rescue ActiveRecord::StatementInvalid
end

class Post < ActiveRecord::Base
  def permalink; "/posts/#{to_param}"; end
  def full_permalink; "http://sin.metaatem.net#{permalink}"; end
  
  def to_metaweblog
    {
      :dateCreated => created_at,
      :userid => 1,
      :postid => id,
      :description => description,
      :title => title,
      :link => "#{full_permalink}",
      :permaLink => "#{full_permalink}",
      :categories => ["General"],
      :date_created_gmt => created_at.getgm,
    }
  end
end

# set utf-8 for outgoing
before_attend do
  header "Content-Type" => "text/html; charset=utf-8"
end

layout do
  <<-HTML
  <html>
  <head>
    <meta http-equiv="Content-type" content="text/html; charset=utf-8">
    <title>Mini Sinatra Blog</title>
    <link rel="alternate" href="feed://subtlety.errtheblog.com/O_o/2d4.xml" type="application/atom+xml"/>
    <style type="text/css" media="screen">
      body { font: 75% "Helvetica", arial, Verdana, sans-serif; background: #FFB03B; }
      h1 { margin: 0; color: #8E2800; }
      h2 { margin-bottom: 0;}
      a { color: #468966; }
      #page { margin: 1em auto; width: 41.667em; border: 0.75em solid #B64926; background: white; padding: 2em; }
      .post { border-bottom: 0.4em double #FFB03B; padding-bottom: 1em;}
      .post .subtitle { padding-bottom: 1em; font-size: 83.333%; display: block;}
      #header, #footer { width: 47em; margin: 0 auto}
      #header h3 { font-size: 320%; margin: 0.5em 0 0 0; font-family: "Georgia";}
      #header h3 a { color: #FFF0A5; text-decoration: none; text-transform: uppercase; letter-spacing: 0.3em; text-shadow: #B64926 0.04em 0.04em;}
    </style>
  </head>
  <body>
    <div id="header"><h3><a href="/">Mini Blogin’</a></h3></div>
    <div id="page">
      <%= yield %>
    </div>
    <div id="footer">&copy; Erik <a href="http://metaatem.net/" alt="kastner">Kastner</a>. Source code on <a href="http://pastie.textmate.org/153325" title="#153325 by Erik Kastner (kastner) - Pastie">pastie</a></div>
  </body>
  </html>
  HTML
end

get '/' do
  res = "<h1>Posts</h1>"
  res += <<-HTML
  <div class="post">
    <p>Welcome. If you’d like to try adding a post. Point your editor at http://sin.metaatem.net/xml with any username.</p>
    <p>You can even upload files. However, you can only upload small files until Rack, or Sinatra or SOMEONE fixes TempFile uploads.</p>
  </div>
  HTML
  
  Post.find(:all, :limit => 20, :order => "created_at DESC").each do |p|
    # hAtom
    res << <<-HTML
    <div class="post hentry">
      <h2><a href="#{p.permalink}" class="entry-title" rel="bookmark">#{p.title}</a></h2>
      <span class="subtitle">Posted by 
        <span class="author vcard fn">#{p.author}</span> on 
        <abbr class="updated" title="#{p.updated_at.getgm.strftime("%Y-%m-%dT%H:%M:%SZ")}">#{p.updated_at.strftime("%D")}</abbr>
      </span>
      <div class="content entry-content">
        #{p.description}
      </div>
    </div>
    
    HTML
  end
  erb res
end

# a single post -- sinatra doesn't do head requests in it's dsl yet. this is also DRY
%w{get head}.each do |meth|
  Sinatra::Event.new(meth.to_sym, '/posts/:id') do
    p = Post.find(params[:id])
    res = "<h1>#{p.title}</h1>"
    res << "#{p.updated_at.strftime("%D")}"
    res << "<p>#{p.description}</p>"
    erb res
  end
end

# metaweblog api handler
post '/xml' do
  xml = @request.env["rack.request.form_vars"]
  if xml.empty?
    hash = @request.env["rack.request.query_hash"]
    xml = (hash.keys + hash.values).join
  end
  
  raise "Nothing supplied" if xml.empty?
  
  call = XMLRPC::Marshal.load_call(xml)
  # convert metaWeblog.getPost to get_post
  method = call[0].gsub(/metaWeblog\.(.*)/, '\1').gsub(/([A-Z])/, '_\1').downcase
  
  header 'Content-Type' => 'text/xml'  
  send(method, call)
end

def get_post(xmlrpc_call)
  begin
    post = Post.find(xmlrpc_call[1][0])
  rescue ActiveRecord::RecordNotFound
    post = Post.find(xmlrpc_call[1][0].gsub(/^.*posts\/(\d+)[^\d].*$/, '\1'))
  end
  XMLRPC::Marshal.dump_response(post.to_metaweblog)
end

def get_recent_posts(xmlrpc_call)
  posts = Post.find(:all, :limit => 10, :order => "created_at DESC")
  XMLRPC::Marshal.dump_response(posts.map{|p| p.to_metaweblog})
end

def new_post(xmlrpc_call)
  data = xmlrpc_call[1]
  # blog_id = data[0]; user = data[1]; pass = data[2]
  post_data = data[3]
  post = Post.create(:author => data[1], :title => post_data["title"], :description => post_data["description"])
  XMLRPC::Marshal.dump_response(post.to_metaweblog)
end

def edit_post(xmlrpc_call)
  data = xmlrpc_call[1]
  post = Post.find(data[0])
  # user = data[1]; pass = data[2]
  post_data = data[3]
  post.update_attributes!(:title => post_data["title"], :description => post_data["description"])
  XMLRPC::Marshal.dump_response(post.to_metaweblog)
end

def get_categories(xmlrpc_call)
  #res = [{ :categoryId => 1,:parentId => 0,:description => "General",:categoryName => "General",:htmlUrl => "http://test.com/categories/1",:rssUrl => "http://test.com/categories/1/feed"}]
  XMLRPC::Marshal.dump_response(res)
end

def new_media_object(xmlrpc_call)
  post_data = xmlrpc_call[1][3]
  name = post_data["name"].gsub(/\//,'')
  AWS::S3::Base.establish_connection!(
    :access_key_id => ENV["AMAZON_ACCESS_KEY_ID"],
    :secret_access_key => ENV["AMAZON_SECRET_ACCESS_KEY"]
  )

  AWS::S3::S3Object.store(name, post_data["bits"], BUCKET, :access => :public_read)
  XMLRPC::Marshal.dump_response({
    :file => name,
    :url => "http://s3.amazonaws.com/#{BUCKET}/#{name}"
  })
end