require 'sinatra'
require 'intercom'
require 'dotenv'
require 'simple_spark'
require 'csv'
require 'json'
require 'haml'
require 'sinatra/form_helpers'

Dotenv.load

DEBUG = ENV["DEBUG"] || nil
BULK_LIMIT = 50

set :show_exceptions, true


use Rack::Auth::Basic, "Restricted Area" do |username, password|
  username == ENV["USERNAME"] and password == ENV["PASSWORD"]
end

get '/' do
  erb :index
end



post '/person' do
  add_params = params["add"]
  id = add_params[:id]
  email = add_params[:email]
  user_id = add_params[:user_id]
  name = add_params[:name]
  data = {}
  @msg = ""
  if add_params[:other_data] != ""
    begin
      # there has to be a better way that to do this.....
      data = JSON.parse(JSON.generate(eval(add_params[:other_data])))
    rescue Exception => e
      @msg = "Invalid JSON: #{e.message}"
    end
  end 
  [:name, :id, :email, :user_id].each{|var|
    data[var] = add_params[var] if !add_params[var].nil?  && add_params[var].strip != "" 
  }
  if !@msg != ""
    init_intercom
    source = get_person_source add_params
    if !source.nil? 
      begin
        @record = format_intercom_object(source.create(data))
      rescue Intercom::ResourceNotFound
        @msg = "Record not found"
      rescue Intercom::IntercomError => e
        @msg = "Intercom error message: #{e.message}"
      rescue Exception => e
        @msg = "Other error: #{e.message}"
      end
    end
  end
  erb :person
end

get '/person' do
  search = {}
  search_params = params["search"]
  [:id, :email, :user_id].each{|var|
    search[var] = search_params[var] if !search_params[var].nil?  && search_params[var].strip != "" 
  } if search_params
  if search.keys.count > 0 then
    init_intercom
    source = get_person_source search_params
    if !source.nil? 
      begin
        @record = format_intercom_object(source.find(search))
      rescue Intercom::ResourceNotFound
        @msg = "Record not found"
      rescue Intercom::IntercomError => e
        @msg = "Intercom error message: #{e.message}"
      rescue Exception => e
        @msg = "Other error: #{e.message}"
      end
    end
  end
  erb :person
end
# unsure how to format this nicely
def format_intercom_object(data)
  create_json_printable_object(JSON::GenericObject.from_hash(data).to_hash)
end
def create_json_printable_object(data)
  data.keys.each{|key|
    if data[key].class == JSON::GenericObject
        data[key] = data[key].to_h
    elsif data[key].class == Array
        data[key].each_with_index{|item,index|
          data[key][index] = create_json_printable_object(item.to_hash) unless item.nil?
        }
    end
  } unless data.keys.nil?
  return data
end

def get_person_source (params)
  case params[:type]
    when "User"
      @intercom.users
    when "Lead"
      @intercom.contacts
    when "Visitor"
      @intercom.visitors
    else
      nil
  end
end



get '/conversation_reassignment' do
  init_intercom
  get_admins
  erb :conversation_reassignment
end

post '/conversation_reassignment' do
  init_intercom
  get_admins

  source_status = params[:reassign][:source_status]
  source_status = (source_status != "closed")
  source = params[:reassign][:source]
  search = {type: 'admin', open: source_status, id: source}
  search[:id] = "nobody" if source.strip == "0"
  puts search.inspect

  destination = params[:reassign][:destination]
  destination_status = params[:reassign][:destination_status]

  action = "close" if (destination_status.strip == "close")
  action = "open" if (destination_status.strip == "open")

  admin = params[:reassign][:admin]

  @intercom.conversations.find_all(search).each {|conversation|
    puts "action: #{action}"
    if action == "close" then
      @intercom.conversations.close(id: conversation.id, admin_id: admin)
    elsif action == "open" then
      @intercom.conversations.open(id: conversation.id, admin_id: admin)
    else
      @intercom.conversations.assign(id: conversation.id, admin_id: admin, assignee_id: destination)
    end
  }

  erb :conversation_reassignment
end

def get_admins
  @admins = @admins || @intercom.admins.all.select{|ad| ad.email.nil? || !ad.email.include?("@bots.intercom.io") } rescue []
end

get '/conversation' do
  get_conversation_details
  erb :conversation, :locals => {:show_email => can_show_email}
end

post '/conversation' do
  get_conversation_details
  @email = params[:email]
  @subject = params[:subject]
  simple_spark = SimpleSpark::Client.new

  # Sandbox details https://developers.sparkpost.com/api/transmissions.html#header-the-sandbox-domain
  # need to currently enable options: {sandbox :true } too
  from_address = ENV["FROM_ADDRESS"] if !ENV["FROM_ADDRESS"].nil?
  from_address = "sender@" + ENV["SPARKPOST_SANDBOX_DOMAIN"] if from_address.nil? || from_address.strip == ""

  @hide_get_transcript_form = true
  properties = {
    recipients:  [{ address: { email: @email }}],
    content:
    { from: { email: from_address },
      subject: @subject,
      html: erb((:conversation),:locals => {:show_email => false}, :layout => false)
    }
  }
  properties['options'] = { sandbox: true } unless (!ENV["SKIP_SPARKPOST_SANDBOX"].nil? && ENV["SKIP_SPARKPOST_SANDBOX"] != "")

  puts properties.inspect
  simple_spark.transmissions.create(properties)
  @show_sent = true
  @hide_get_transcript_form = false
  erb :conversation, :locals => {:show_email => can_show_email}
end

def can_show_email
  ( (!ENV["FROM_ADDRESS"].nil? && ENV["FROM_ADDRESS"] != "") ||
    (!ENV["SPARKPOST_SANDBOX_DOMAIN"].nil? && ENV["SPARKPOST_SANDBOX_DOMAIN"] != "")
  )  &&
  (!ENV["SPARKPOST_API_KEY"].nil? && ENV["SPARKPOST_API_KEY"] != "")
end
def get_author_type author
  type = "admin"
  if author.class.to_s == "Intercom::Lead" then
    type = "lead"
  elsif author.class.to_s == "Intercom::User" then
    type = "user"
  end
  type
end

def is_nobody author
  author.id.nil? && get_author_type(author) == "admin"
end

def author_details author
  {type: get_author_type(author), id: author.id}
end

def get_conversation_details
  id = params[:id]
  @show_selective = params[:show_selective];
  if @show_selective == "true" then
    @show_selective = "1"
  end
  if id.nil? then
    @conversation = nil
  else
    @conversation = conversation(id)
    @authors = {"user" => {}, "lead" => {}, "admin" => {}}
    unless @conversation.nil?
      if @conversation.conversation_parts then
        @conversation.conversation_parts.each{|p|
          tmp = author_details p.author
          @authors[tmp[:type]][tmp[:id]] = tmp
          if p.assigned_to then
            @authors["admin"][p.assigned_to.id] = 1
          end
        }
      end
      tmp = author_details @conversation.conversation_message.author
      @authors[tmp[:type]][tmp[:id]] = 1
    end
    @authors_details = get_all_author_details
  end
end

def get_all_author_details
  init_intercom
  authors_details = {"user" => {}, "lead" => {}, "admin" => {}}
  @authors["lead"].each{|id, obj|
    data = @intercom.contacts.find(:id => id)
    authors_details["lead"][id] = data.name || data.pseudonym || data.email || data.id
  }
  @authors["user"].each{|id, obj|
    data = @intercom.users.find(:id => id)
    authors_details["user"][id] = data.name || data.pseudonym || data.user_id || data.email || data.id
  }

  admin_ids = []
  @authors["admin"].each{|id,obj|
    admin_ids << id
  }

  data = get_admins.select {|admin| admin_ids.include?(admin.id)}
  data.each{|admin|
    authors_details["admin"][admin.id] = admin.name || admin.email
  }
  authors_details
end

def init_intercom
  if @intercom.nil? then
    app_id = ENV["APP_ID"]
    api_key = ""
    api_key = ENV["API_KEY"] if (!ENV["API_KEY"].nil? && ENV["API_KEY"])
    @intercom = Intercom::Client.new(app_id: app_id, api_key: api_key)
  end
end

def conversation (conversation_id)
  init_intercom
  begin
    @intercom.conversations.find(:id => conversation_id)

  rescue Exception => e 
    nil
  end
end


# Handle POST-request (Receive and save the uploaded file)
get "/unsubscribe" do
  erb :unsubscribe
end

# Handle POST-request (Receive and save the uploaded file)
post "/unsubscribe" do

  init_intercom
  status = params[:unsubscribe]
  identifier = params[:identifier]

  items = []
  @jobs = []

  # process uploaded file
  if params[:file] then
    file = params[:file][:tempfile]
    CSV.foreach(file) do |row|
      item = { unsubscribed_from_emails: status}
      item[identifier] = row.first.strip
      items << item
      if items.count == BULK_LIMIT then
        puts items.inspect
        @jobs << @intercom.users.submit_bulk_job(create_items: items)
        items = []
      end
    end
  end

  # process manual text
  params[:manual_input].each_line{|line|
    item = { unsubscribed_from_emails: status}
    item[identifier] = line.strip
    items << item
    if items.count == BULK_LIMIT then
      puts items.inspect
      @jobs << @intercom.users.submit_bulk_job(create_items: items)
      items = []
    end
  }

  # proces any remaining
  if items.count > 0 then
    puts items.inspect
    @jobs << @intercom.users.submit_bulk_job(create_items: items)
    items = []
  end
  erb :unsubscribe
end


helpers do
  def author_is_admin (author)
    "admin" == get_author_type(author)
  end
  def author_is_admin (author)
    "admin" == get_author_type(author)
  end
  def author_name (author, author_list)
    type = get_author_type(author)
    id = author.id
    if is_nobody(author) then
      "Nobody"
    else
      author_list[type][id]
    end
  end
end
