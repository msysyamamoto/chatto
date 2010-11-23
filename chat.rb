# -*- coding: utf-8 -*-
require 'uri'
require 'rubygems'
require 'sinatra'
require 'haml'
require 'sass'
require 'json'
require 'twitter'
require 'pusher'
require 'rack-flash'
require 'pp'

# user_id, screen_name が欲しいので
# ここで設定している @access_token.params から取得できる
class Twitter::OAuth
  def authorize_from_request(rtoken, rsecret, verifier_or_pin)
    request_token = ::OAuth::RequestToken.new(signing_consumer, rtoken, rsecret)
    @access_token = request_token.get_access_token(:oauth_verifier => verifier_or_pin)
    @atoken, @asecret = @access_token.token, @access_token.secret
  end
end

configure do
  enable :run # for Ruby 1.9.2

  set :views, File.dirname(__FILE__) + '/views'
  set :public, File.dirname(__FILE__) + '/public'

  #enable :sessions
  use Rack::Session::Cookie,
      :expire_after => 3600 * 24,
      :secret       => ENV['CHAT_SESSION_KEY'] || Digest::SHA1.hexdigest(rand.to_s)

  use Rack::Flash

  set :conf, YAML.load_file('config.yml') rescue nil || {}

  # Pusher API Credentials
  Pusher.app_id = ENV['PUSHER_APPID']  || settings.conf['pusher']['app_id']
  Pusher.key    = ENV['PUSHER_KEY']    || settings.conf['pusher']['key']
  Pusher.secret = ENV['PUSHER_SECRET'] || settings.conf['pusher']['secret']
end

before do
  next if request.path_info =~ /(css|json|ico)$/

  @user = session[:user] || {}

  @oauth = Twitter::OAuth.new(
    ENV['TWITTER_CONSUMERKEY']    || settings.conf['twitter']['consumer_key'],
    ENV['TWITTER_CONSUMERSECRET'] || settings.conf['twitter']['consumer_secret'],
    :sign_in => true,
    :signing_endpoint => 'https://api.twitter.com'
  )

=begin
  # twitter に投稿する必要がでてきたときに
  if session[:access_token]
    @oauth.authorize_from_access(session[:access_token], session[:access_token_secret])
    @twitter = Twitter::Base.new(@oauth)
  else
    @twitter = nil
  end
=end
end

get '/login' do
  begin
    request_token = @oauth.request_token(
        :oauth_callback => ENV['TWITTER_CALLBACKURL'] || settings.conf['twitter']['callback_url']
    )
  rescue OAuth::Unauthorized => exp
    pp exp
    flash[:notice] = 'Oops! Failed authentication.'
    redirect '/'
  end

  session[:request_token]        = request_token.token
  session[:request_token_secret] = request_token.secret
  session[:access_token]         = nil
  session[:access_token_secret]  = nil
  session[:user]                 = nil
  redirect request_token.authorize_url
end

get '/auth' do
  begin
    @oauth.authorize_from_request(
      session[:request_token],
      session[:request_token_secret],
      params[:oauth_verifier]
    )
  rescue OAuth::Unauthorized => exp
    pp exp
    flash[:notice] = 'Oops! Failed authentication.'
    redirect '/'
  end

  access_token = @oauth.access_token 
  session[:request_token]        = nil
  session[:request_token_secret] = nil
  session[:access_token]         = access_token.token
  session[:access_token_secret]  = access_token.secret

  begin
    tw = Twitter::Base.new(@oauth)
    # Twitter::OAuth をオーバーライドしているのはここのため
    # access_token.params で user_id がとれる
    prof = tw.user(access_token.params[:user_id].to_i)
  rescue => exp
    pp exp
    flash[:notice] = 'Oops! Failed Twitter API.'
    redirect '/'
  end
  
  @user = {
    :id           => prof.id,
    :name         => prof.screen_name,
    :image_url    => prof.profile_image_url,
    :bg_image_url => prof.profile_background_image_url,
  }
  session[:user] = @user

  # チャットルームに入っていない場合は index へ
  redirect '/' unless session[:room]

  redirect '/chat'
end

get '/logout' do
  session[:request_token]        = nil
  session[:request_token_secret] = nil
  session[:access_token]         = nil
  session[:access_token_secret]  = nil
  session[:user]                 = nil

  # チャットルームに入っていない場合は index へ
  redirect '/' unless session[:room]

  @user = {}
  redirect '/chat'
end

=begin
# css 開発時
get '/css/chat.css' do
  content_type 'text/css', :charset => 'utf-8'
  sass :chat
end
=end

get '/' do
  session[:room] = nil 
	haml :index, :locals => {:index => true}
end

get '/chat' do
  redirect '/' if session[:room].to_s.size <= 0

  haml :chat, :locals => {:index => false}
end

post '/chat' do
  # Every channel is identified by a name containing only alphanumeric characters, '-', '_' and ':'.
  # 20 は勝手に決めた
  unless params[:room] =~ /^[-:\w]{1,20}$/
    flash[:notice] = 'チャットルームには アルファベット, 数字, "-", "_", ":" だけが使えます。'
    redirect '/'
  end
  session[:room] = params[:room] 
  haml :chat, :locals => {:index => false}
end

get '/room.json' do
  room = session[:room].to_s
  {'name' => room}.to_json
end

post '/post' do
  return unless params[:text]
  return unless session[:room]
 
  channel = 'presence-' + URI.escape(session[:room].to_s)
  chat = {
    'login'     => @user[:name] ? true : false,
    'name'      => @user[:name] || params[:name], 
    'text'      => params[:text],
    'image_url' => @user[:image_url]
  }

  begin
    Pusher[channel].trigger('chat_post', chat.to_json)
  rescue => e
    pp e
    500
  end
end

post '/pusher/auth' do
  if @user[:name]
    user_id   = @user[:name]
    user_name = @user[:name]
    image_url = @user[:image_url]
    login     = true

  # 未ログイン時は anonymous + ランダムな値
  # twitter の名前は"-"は使えないの、偶然重なることはない
  else
    user_id   = 'anonymous-' + Time.new.to_f.to_s.gsub(/\./, '') + rand(1000).to_s
    user_name = 'anonymous'
    image_url = '/img/anonymous.png' 
    login     = false
  end

  auth = Pusher[params[:channel_name]].authenticate(
        params[:socket_id],
        :user_id   => user_id,
        :user_info => {
          :name      => user_name,
          :image_url => image_url,
          :login     => login
        }
  )
  auth.to_json
end
