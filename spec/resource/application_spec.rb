require 'spec_helper'
include UUIDTools

describe Stormpath::Resource::Application, :vcr do
  let(:app) { test_api_client.applications.create name: random_application_name, description: 'Dummy desc.' }
  let(:application) { test_api_client.applications.get app.href }
  let(:directory) { test_api_client.directories.create name: random_directory_name }
  let(:directory_with_verification) { test_directory_with_verification }

  before do
   test_api_client.account_store_mappings.create({ application: app, account_store: directory,
      list_index: 1, is_default_account_store: true, is_default_group_store: true })
  end

  after do
    application.delete if application
    directory.delete if directory
  end

  it "instances should respond to attribute property methods" do

    expect(application).to be_a Stormpath::Resource::Application

    [:name, :description, :status].each do |property_accessor|
      expect(application).to respond_to(property_accessor)
      expect(application).to respond_to("#{property_accessor}=")
      expect(application.send property_accessor).to be_a String
    end

    expect(application.tenant).to be_a Stormpath::Resource::Tenant
    expect(application.default_account_store_mapping).to be_a Stormpath::Resource::AccountStoreMapping
    expect(application.default_group_store_mapping).to be_a Stormpath::Resource::AccountStoreMapping
    expect(application.custom_data).to be_a Stormpath::Resource::CustomData

    expect(application.groups).to be_a Stormpath::Resource::Collection
    expect(application.accounts).to be_a Stormpath::Resource::Collection
    expect(application.password_reset_tokens).to be_a Stormpath::Resource::Collection
    expect(application.verification_emails).to be_a Stormpath::Resource::Collection
    expect(application.account_store_mappings).to be_a Stormpath::Resource::Collection
  end

  describe '.load' do
    let(:url) do
      uri = URI(application.href)
      credentialed_uri = URI::HTTPS.new(
        uri.scheme, "#{test_api_key_id}:#{test_api_key_secret}", uri.host,
        uri.port, uri.registry, uri.path, uri.query, uri.opaque, uri.fragment
      )
      credentialed_uri.to_s
    end

    it "raises a LoadError with an invalid url" do
      expect {
        Stormpath::Resource::Application.load 'this is an invalid url'
      }.to raise_error(Stormpath::Resource::Application::LoadError)
    end

    it "instantiates client and application objects from a composite URL" do
      loaded_application = Stormpath::Resource::Application.load(url)
      expect(loaded_application).to eq(application)
    end
  end

  describe 'application_associations' do

    context '#accounts' do
      let(:account) { application.accounts.create build_account}

      after do
        account.delete if account
      end

      it 'should be able to create an account' do
        expect(application.accounts).to include(account)
        expect(application.default_account_store_mapping.account_store.accounts).to include(account)
      end

      it 'should be able to create and fetch the account' do
        expect(application.accounts.get account.href).to be
      end
    end

    context '#groups' do
      let(:group) { application.groups.create name: random_group_name }

      after do
        group.delete if group
      end

      it 'should be able to create a group' do
        expect(application.groups).to include(group)
        expect(application.default_group_store_mapping.account_store.groups).to include(group)
      end

      it 'should be able to create and fetch a group' do
        expect(application.groups.get group.href).to be
      end
    end

  end

  describe '#authenticate_account' do
    let(:account) do
      directory.accounts.create build_account(password: 'P@$$w0rd')
    end

    let(:login_request) do
      Stormpath::Authentication::UsernamePasswordRequest.new account.username, password
    end

    let(:authentication_result) do
      application.authenticate_account login_request
    end

    after do
      account.delete if account
    end

    context 'given a valid username and password' do
      let(:password) {'P@$$w0rd' }

      it 'returns an authentication result' do
        expect(authentication_result).to be
        expect(authentication_result.account).to be
        expect(authentication_result.account).to be_kind_of Stormpath::Resource::Account
        expect(authentication_result.account.email).to eq(account.email)
      end
    end

    context 'given an invalid username and password' do
      let(:password) { 'b@dP@$$w0rd' }

      it 'raises an error' do
        expect { authentication_result }.to raise_error Stormpath::Error
      end
    end
  end

  describe '#authenticate_account_with_an_account_store_specified' do
    let(:password) {'P@$$w0rd' }

    let(:authentication_result) { application.authenticate_account login_request }

    after do
      account.delete if account
    end

    context 'given a proper directory' do
      let(:account) { directory.accounts.create build_account(password: 'P@$$w0rd') }

      let(:login_request) do
        Stormpath::Authentication::UsernamePasswordRequest.new account.username, password, account_store: directory
      end

      it 'should return an authentication result' do
        expect(authentication_result).to be
        expect(authentication_result.account).to be
        expect(authentication_result.account).to be_kind_of Stormpath::Resource::Account
        expect(authentication_result.account.email).to eq(account.email)
      end
    end

    context 'given a wrong directory' do
      let(:new_directory) { test_api_client.directories.create name: random_directory_name('new') }

      let(:account) { new_directory.accounts.create build_account(password: 'P@$$w0rd') }

      let(:login_request) do
        Stormpath::Authentication::UsernamePasswordRequest.new account.username, password, account_store: directory
      end

      after do
        new_directory.delete if new_directory
      end

      it 'raises an error' do
        expect { authentication_result }.to raise_error Stormpath::Error
      end
    end

    context 'given a group' do
      let(:group) {directory.groups.create name: random_group_name }

      let(:account) { directory.accounts.create build_account(password: 'P@$$w0rd') }

      let(:login_request) do
        Stormpath::Authentication::UsernamePasswordRequest.new account.username, password, account_store: group
      end

      before do
        test_api_client.account_store_mappings.create({ application: application, account_store: group })
      end

      after do
        group.delete if group
      end

      it 'and assigning the account to it, should return a authentication result' do
        group.add_account account
        expect(authentication_result).to be
        expect(authentication_result.account).to be
        expect(authentication_result.account).to be_kind_of Stormpath::Resource::Account
        expect(authentication_result.account.email).to eq(account.email)
      end

      it 'but not assigning the account to, it should raise an error' do
        expect { authentication_result }.to raise_error Stormpath::Error
      end
    end

  end

  describe '#send_password_reset_email' do
    context 'given an email' do
      context 'of an exisiting account on the application' do
        let(:account) { directory.accounts.create build_account  }

        let(:sent_to_account) { application.send_password_reset_email account.email }

        after do
          account.delete if account
        end

        it 'sends a password reset request of the account' do
          expect(sent_to_account).to be
          expect(sent_to_account).to be_kind_of Stormpath::Resource::Account
          expect(sent_to_account.email).to eq(account.email)
        end
      end

      context 'of a non exisitng account' do
        it 'raises an exception' do
          expect do
            application.send_password_reset_email "test@example.com"
          end.to raise_error Stormpath::Error
        end
      end
    end
  end

  describe '#verification_emails' do
    let(:directory_with_verification) { test_directory_with_verification }

    before do
      test_api_client.account_store_mappings.create({ application: app, account_store: directory_with_verification,
        list_index: 1, is_default_account_store: false, is_default_group_store: false })
    end

    let(:account) do
      directory_with_verification.accounts.create({
        email: random_email,
        given_name: 'Ruby SDK',
        password: 'P@$$w0rd',
        surname: 'SDK',
        username: random_user_name
      })
    end

    let(:verification_emails) do
      application.verification_emails.create(login: account.email)
    end

    after do
      account.delete if account
    end

    it 'returnes verification email' do
      expect(verification_emails).to be_kind_of Stormpath::Resource::VerificationEmail
    end
  end

  describe '#create_login_attempt' do
    let(:account) do
      directory.accounts.create({
        email: random_email,
        given_name: 'Ruby SDK',
        password: 'P@$$w0rd',
        surname: 'SDK',
        username: random_user_name
      })
    end

    context 'valid credentials' do
      let(:login_attempt) { application.create_login_attempt({type: "basic", username: account.email, password: "P@$$w0rd"}) }

      it 'returns login attempt response' do
        expect(login_attempt).to be_kind_of Stormpath::Resource::LoginAttempt
      end

      it 'containes account data' do
        expect(login_attempt.account["href"]).to eq(account.href) 
      end
    end

    context 'with organization as account store option' do
      let()
      let(:login_attempt) do
        application.create_login_attempt({
          type: "basic",
          username: account.email,
          password: "P@$$w0rd",
          account_store: {
            name_key: organization.name
          }
        })
      end

      it 'returns login attempt response' do
      end

      it 'containes account data' do
      end
    end

    context 'with invalid credentials' do
      let(:login_attempt) { application.create_login_attempt({type: "basic", username: account.email, password: "invalid"}) }

      it 'returns stormpath error' do
        expect { 
          login_attempt 
        }.to raise_error(Stormpath::Error)
      end 
    end
  end

  describe '#verify_password_reset_token' do
    let(:account) do
      directory.accounts.create({
        email: random_email,
        given_name: 'Ruby SDK',
        password: 'P@$$w0rd',
        surname: 'SDK',
        username: random_user_name
      })
    end

    let(:password_reset_token) do
      application.password_reset_tokens.create(email: account.email).token
    end

    let(:reset_password_account) do
      application.verify_password_reset_token password_reset_token
    end

    after do
      account.delete if account
    end

    it 'retrieves the account with the reset password' do
      expect(reset_password_account).to be
      expect(reset_password_account.email).to eq(account.email)
    end

    context 'and if the password is changed' do
      let(:new_password) { 'N3wP@$$w0rd' }

      let(:login_request) do
        Stormpath::Authentication::UsernamePasswordRequest.new account.username, new_password
      end

      let(:expected_email) { 'test2@example.com' }

      let(:authentication_result) do
        application.authenticate_account login_request
      end

      before do
        reset_password_account.password = new_password
        reset_password_account.save
      end

      it 'can be successfully authenticated' do
        expect(authentication_result).to be
        expect(authentication_result.account).to be
        expect(authentication_result.account).to be_kind_of Stormpath::Resource::Account
        expect(authentication_result.account.email).to eq(account.email)
      end
    end
  end

  describe '#create_application_with_custom_data' do
    it 'creates an application with custom data' do
      application.custom_data["category"] = "classified"
      application.save

      expect(application.custom_data["category"]).to eq("classified")
    end
  end

  describe '#create_id_site_url' do
    let(:jwt_token) { JWT.encode({
        'iat' => Time.now.to_i,
        'jti' => UUID.method(:random_create).call.to_s,
        'aud' => test_api_key_id,
        'sub' => application.href,
        'cb_uri' => 'http://localhost:9292/redirect',
        'path' => '',
        'state' => ''
      }, test_api_key_secret, 'HS256')
    }

    let(:create_id_site_url_result) do
      options = { callback_uri: 'http://localhost:9292/redirect' }
      application.create_id_site_url options
    end

    it 'should create a url with jwtRequest' do
      expect(create_id_site_url_result).to include('jwtRequest')
    end

    it 'should create a request to /sso' do
      expect(create_id_site_url_result).to include('/sso')
    end

    it 'should create a jwtRequest that is signed wit the client secret' do
      uri = Addressable::URI.parse(create_id_site_url_result)
      jwt_token = JWT.decode(uri.query_values["jwtRequest"], test_api_key_secret).first

      expect(jwt_token["iss"]).to eq test_api_key_id
      expect(jwt_token["sub"]).to eq application.href
      expect(jwt_token["cb_uri"]).to eq 'http://localhost:9292/redirect'
    end

    context 'with logout option' do
      it 'shoud create a request to /sso/logout' do
      end
    end

    context 'without providing cb_uri' do
      let(:create_id_site_url_result) do
        options = { callback_uri: '' }
        application.create_id_site_url options
      end

      it 'should raise Stormpath Error with correct id_site error data' do
        begin
          create_id_site_url_result
        rescue Stormpath::Error => error
          expect(error.status).to eq(400)
          expect(error.code).to eq(400)
          expect(error.message).to eq("The specified callback URI (cb_uri) is not valid")
          expect(error.developer_message).to eq("The specified callback URI (cb_uri) is not valid. Make sure the "\
            "callback URI specified in your ID Site configuration matches the value specified.")
        end 
      end
    end
  end

  describe '#handle_id_site_callback' do
    let(:callback_uri_base) { 'http://localhost:9292/somwhere?jwtResponse=' }

    context 'without the response_url provided' do
      it 'should raise argument error' do
        expect { application.handle_id_site_callback(nil) }.to raise_error(ArgumentError)
      end
    end

    context 'with a valid jwt response' do
      let(:jwt_token) { JWT.encode({
          'iat' => Time.now.to_i,
          'aud' => test_api_key_id,
          'sub' => application.href,
          'path' => '',
          'state' => '',
          'isNewSub' => true,
          'status' => "REGISTERED"
        }, test_api_key_secret, 'HS256')
      }

      before do
        @site_result = application.handle_id_site_callback(callback_uri_base + jwt_token)
      end

      it 'should return IdSiteResult object' do
        expect(@site_result).to be_kind_of(Stormpath::IdSite::IdSiteResult)
      end

      it 'should set the correct account on IdSiteResult object' do
        expect(@site_result.account_href).to eq(application.href)
      end

      it 'should set the correct status on IdSiteResult object' do
        expect(@site_result.status).to eq("REGISTERED")
      end

      it 'should set the correct state on IdSiteResult object' do
        expect(@site_result.state).to eq("")
      end

      it 'should set the correct is_new_account on IdSiteResult object' do
        expect(@site_result.new_account?).to eq(true)
      end
    end

    context 'with an expired token' do
      let(:jwt_token) { JWT.encode({
          'iat' => Time.now.to_i,
          'aud' => test_api_key_id,
          'sub' => application.href,
          'path' => '',
          'state' => '',
          'exp' => Time.now.to_i - 1,
          'isNewSub' => true,
          'status' => "REGISTERED"
        }, test_api_key_secret, 'HS256')
      }

      it 'should raise Stormpath Error with correct data' do
        begin
          application.handle_id_site_callback(callback_uri_base + jwt_token)
        rescue Stormpath::Error => error
          expect(error.status).to eq(400)
          expect(error.code).to eq(10011)
          expect(error.message).to eq("Token is invalid")
          expect(error.developer_message).to eq("Token is no longer valid because it has expired")
        end
      end

      it 'should raise expiration error' do
        expect {
          application.handle_id_site_callback(callback_uri_base + jwt_token)
        }.to raise_error(Stormpath::Error)
      end
    end

    context 'with a different client id (aud)' do
      let(:jwt_token) { JWT.encode({
          'iat' => Time.now.to_i,
          'aud' => UUID.method(:random_create).call.to_s,
          'sub' => application.href,
          'path' => '',
          'state' => '',
          'isNewSub' => true,
          'status' => "REGISTERED"
        }, test_api_key_secret, 'HS256')
      }

      it 'should raise error' do
        expect {
          application.handle_id_site_callback(callback_uri_base + jwt_token)
        }.to raise_error(Stormpath::Error)
      end

      it 'should raise Stormpath Error with correct id_site error data' do
        begin
          application.handle_id_site_callback(callback_uri_base + jwt_token)
        rescue Stormpath::Error => error
          expect(error.status).to eq(400)
          expect(error.code).to eq(10012)
          expect(error.message).to eq("Token is invalid")
          expect(error.developer_message).to eq("Token is invalid because the issued at time (iat) "\
            "is after the current time")
        end
      end
    end

    context 'with an invalid exp value' do
      let(:jwt_token) { JWT.encode({
          'iat' => Time.now.to_i,
          'aud' => test_api_key_id,
          'sub' => application.href,
          'path' => '',
          'state' => '',
          'exp' => 'not gona work',
          'isNewSub' => true,
          'status' => "REGISTERED"
        }, test_api_key_secret, 'HS256')
      }

      it 'should error with the stormpath error' do  
        expect {
          application.handle_id_site_callback(callback_uri_base + jwt_token)
        }.to raise_error(Stormpath::Error)
      end
    end

    context 'with an invalid signature' do
      let(:jwt_token) { JWT.encode({
          'iat' => Time.now.to_i,
          'aud' => test_api_key_id,
          'sub' => application.href,
          'path' => '',
          'state' => '',
          'isNewSub' => true,
          'status' => "REGISTERED"
        }, 'false key', 'HS256')
      }

      it 'should reject the signature' do
        expect {
          application.handle_id_site_callback(callback_uri_base + jwt_token)
        }.to raise_error(JWT::DecodeError)
      end
    end
  end

  describe '#oauth_authenticate' do
    let(:account_data) { build_account }
    let(:aquire_token) do
      application.oauth_authenticate({ 
        body: { 
          username: account_data[:email], 
          grant_type: 'password', 
          password: account_data[:password] 
        } 
      })
    end

    before do
      application.accounts.create account_data
    end
  
    context 'generate access token' do
      let(:oauth_data) { { body: { username: account_data[:email], grant_type: 'password', password: account_data[:password] } } }
      let(:oauth_authenticate) { application.oauth_authenticate(oauth_data) }

      it 'should return access token response' do
        expect(oauth_authenticate).to be_kind_of(Stormpath::Resource::AccessToken)
      end

      it 'response should contain token data' do
        expect(oauth_authenticate.access_token).not_to be_empty
        expect(oauth_authenticate.refresh_token).not_to be_empty
        expect(oauth_authenticate.token_type).not_to be_empty
        expect(oauth_authenticate.expires_in).not_to be_nil
        expect(oauth_authenticate.stormpath_access_token_href).not_to be_empty
      end
    end

    context 'refresh token' do
      let(:oauth_data) { { body: { username: account_data[:email], grant_type: 'refresh_token', refresh_token: aquire_token.refresh_token} } }
      let(:oauth_authenticate) { application.oauth_authenticate(oauth_data) }

      it 'should return access token response with refreshed token' do
        expect(oauth_authenticate).to be_kind_of(Stormpath::Resource::AccessToken)
      end

      it 'refreshed token is not the same as previous one' do
        expect(oauth_authenticate.access_token).not_to be_equal(aquire_token.access_token)
      end

      it 'returens success with data' do
        expect(oauth_authenticate.access_token).not_to be_empty
        expect(oauth_authenticate.refresh_token).not_to be_empty
        expect(oauth_authenticate.token_type).not_to be_empty
        expect(oauth_authenticate.expires_in).not_to be_nil
        expect(oauth_authenticate.stormpath_access_token_href).not_to be_empty
      end
    end

    context 'validate access token' do
      let(:oauth_data) { { headers: { authorization: aquire_token.access_token } } } 
      let(:oauth_authenticate) { application.oauth_authenticate(oauth_data) }

      it 'should return authentication result response' do
        expect(oauth_authenticate).to be_kind_of(Stormpath::Jwt::AuthenticationResult)
      end

      it 'returens success on valid token' do
        expect(oauth_authenticate.href).not_to be_empty 
        expect(oauth_authenticate.account).not_to be_empty 
        expect(oauth_authenticate.application).not_to be_empty 
        expect(oauth_authenticate.jwt).not_to be_empty 
        expect(oauth_authenticate.tenant).not_to be_empty 
        expect(oauth_authenticate.expanded_jwt).not_to be_empty 
      end
    end

    context 'delete token' do
      it 'after token was deleted user can authenticate with the same token' do
        access_token = aquire_token.access_token
        aquire_token.delete

        expect {
          response = application.oauth_authenticate( { headers: { authorization: access_token } } )
        }.to raise_error(Stormpath::Error)
      end
    end
  end
end
