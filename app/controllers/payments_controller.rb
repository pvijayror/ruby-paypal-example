class PaymentsController < ApplicationController
  # GET /payments
  # GET /payments.json
  def index
    @payments = Payment.all

    respond_to do |format|
      format.html # index.html.erb
      format.json { render json: @payments }
    end
  end

  # GET /payments/1
  # GET /payments/1.json
  def show
    @payment = Payment.find(params[:id])

    paypal = Paypal.new(APP_CONFIG['username'],APP_CONFIG['password'],APP_CONFIG['signature'],APP_CONFIG['url'].to_sym)
    @paypal_result = paypal.do_get_recurring_payments_profile_details(@payment.profile, {})

    Rails.logger.debug "PROFILE DETAILS:"+@paypal_result.inspect

    # {"PROFILEID"=>"I-C07L0WXLH25Y", 
    # "STATUS"=>"Active"
    # "AUTOBILLOUTAMT"=>"NoAutoBill"
    # "DESC"=>"_Why's Ruby Camping Adventures - Monthly Tips And Tricks For Camping Development"
    # "MAXFAILEDPAYMENTS"=>"0"
    # "SUBSCRIBERNAME"=>"Will Bradley"
    # "PROFILESTARTDATE"=>"2013-05-01T07:00:00Z"
    # "PROFILEREFERENCE"=>"INV20091122"
    # "NEXTBILLINGDATE"=>"2013-05-01T10:00:00Z"
    # "NUMCYCLESCOMPLETED"=>"0"
    # "NUMCYCLESREMAINING"=>"11"
    # "OUTSTANDINGBALANCE"=>"0.00"
    # "FAILEDPAYMENTCOUNT"=>"0"
    # "TRIALAMTPAID"=>"0.00"
    # "REGULARAMTPAID"=>"0.00"
    # "AGGREGATEAMT"=>"0.00"
    # "AGGREGATEOPTIONALAMT"=>"0.00"
    # "FINALPAYMENTDUEDATE"=>"2014-03-01T10:00:00Z"
    # "TIMESTAMP"=>"2013-04-30T08:56:47Z"
    # "CORRELATIONID"=>"e305cb3e7287c"
    # "ACK"=>"Success"
    # "VERSION"=>"74.0"
    # "BUILD"=>"5650305"
    # "SHIPTOSTREET"=>"1 Main St"
    # "SHIPTOCITY"=>"San Jose"
    # "SHIPTOSTATE"=>"CA"
    # "SHIPTOZIP"=>"95131"
    # "SHIPTOCOUNTRYCODE"=>"US"
    # "SHIPTOCOUNTRY"=>"US"
    # "SHIPTOCOUNTRYNAME"=>"United States"
    # "SHIPADDRESSOWNER"=>"PayPal"
    # "SHIPADDRESSSTATUS"=>"Unconfirmed"
    # "BILLINGPERIOD"=>"Month"
    # "BILLINGFREQUENCY"=>"1"
    # "TOTALBILLINGCYCLES"=>"11"
    # "CURRENCYCODE"=>"USD"
    # "AMT"=>"5.00"
    # "SHIPPINGAMT"=>"0.00"
    # "TAXAMT"=>"0.00"
    # "REGULARBILLINGPERIOD"=>"Month"
    # "REGULARBILLINGFREQUENCY"=>"1"
    # "REGULARTOTALBILLINGCYCLES"=>"11"
    # "REGULARCURRENCYCODE"=>"USD"
    # "REGULARAMT"=>"5.00"
    # "REGULARSHIPPINGAMT"=>"0.00"
    # "REGULARTAXAMT"=>"0.00"}


    respond_to do |format|
      if @paypal_result['ACK'] == 'Success'
        format.html # show.html.erb
        format.json { render json: @payment }
      else
        format.html { redirect_to payments_url, notice: 'There was a problem contacting PayPal. This issue has been logged.' }
        format.json { render json: @payment.errors, status: :unprocessable_entity }
      end
    end
  end

  # GET /payments/new
  # GET /payments/new.json
  def new
    @payment = Payment.new

    paypal = Paypal.new(APP_CONFIG['username'],APP_CONFIG['password'],APP_CONFIG['signature'],APP_CONFIG['url'].to_sym)

    subscription_request = {
      "PAYMENTACTION" => "Sale",
      "L_BILLINGTYPE0" => "RecurringPayments",
      "DESC" => "_Why's Ruby Camping Adventures",
      "L_BILLINGAGREEMENTDESCRIPTION0" => "_Why's Ruby Camping Adventures - Monthly Tips And Tricks For Camping Development"
    }

    response = paypal.set_express_checkout(
      return_url='http://localhost:3000/payments/confirmed',
      cancel_url='http://localhost:3000/payments/aborted',
      amount='5.00',
      currency='USD',
      other_params=subscription_request)

    Rails.logger.debug "SETEXPRESSCHECKOUT:"+response.inspect

    @token = (response.ack == 'Success') ? response['TOKEN'] : ''

    respond_to do |format|
      if response['ACK'] == 'Success'
        format.html # new.html.erb
        format.json { render json: @payment }
      else
        Rails.logger.warn "SETEXPRESSCHECKOUT ERROR:"+response.inspect
        format.html { redirect_to payments_url, notice: 'There was a problem contacting PayPal. This issue has been logged.' }
        format.json { render json: @payment.errors, status: :unprocessable_entity }
      end
    end
  end

  def confirmed
    token = params[:token]

    paypal = Paypal.new(APP_CONFIG['username'],APP_CONFIG['password'],APP_CONFIG['signature'],APP_CONFIG['url'].to_sym)

    response = paypal.do_get_express_checkout_details(token)

    error = false

    if response['ACK'] != 'Success'
      Rails.logger.warn "GETEXPRESSCHECKOUT ERROR:"+response.inspect
      error = true
    else
      Rails.logger.debug "GETEXPRESSCHECKOUT:"+response.inspect

      response = paypal.do_express_checkout_payment(token=token,
        payment_action='Sale',
        payer_id=response['PAYERID'],
        amount='5.00')
      #transaction_id = response['TRANSACTIONID']

      if response['ACK'] != 'Success'
        Rails.logger.warn "DOEXPESSCHECKOUT ERROR:"+response.inspect
        error = true
      else
        Rails.logger.debug "DOEXPESSCHECKOUT:"+response.inspect

        response = paypal.do_create_recurring_payments_profile(token,
          start_date=(Time.parse(response['TIMESTAMP']) + 1.minute).iso8601, # Start date has to be in the future according to PayPal
          profile_reference='INV20091122',
          description="_Why's Ruby Camping Adventures - Monthly Tips And Tricks For Camping Development",
          billing_period='Month',
          billing_frequency=1,
          total_billing_cycles=nil, # nil/0 = infinite
          amount='5.00',
          currency='USD')

        if response['ACK'] != 'Success'
          Rails.logger.warn "CREATERECURRINGPAYMENT ERROR:"+response.inspect
          error = true
        else
          Rails.logger.debug "CREATERECURRINGPAYMENT:"+response.inspect

          profile_id = response['PROFILEID']

          @payment = Payment.new({profile: profile_id})

          unless @payment.save
            Rails.logger.warn "Payment Save ERROR:"+response.inspect
            error = true
          end
        end
      end
    end

    respond_to do |format|
      unless error
        format.html { redirect_to payments_url, notice: 'Payment was successfully created.' }
        format.json { render json: @payment, status: :created, location: @payment }
      else
        @payment.errors.add_to_base "There was a problem processing your subscription. This issue has been logged."
        format.html { redirect_to payments_url }
        format.json { render json: @payment.errors, status: :unprocessable_entity }
      end
    end
  end

  # GET /payments/1/edit
  # def edit
  #   @payment = Payment.find(params[:id])
  # end

  # POST /payments
  # POST /payments.json
  # def create
  #   @payment = Payment.new(params[:payment])

  #   respond_to do |format|
  #     if @payment.save
  #       format.html { redirect_to @payment, notice: 'Payment was successfully created.' }
  #       format.json { render json: @payment, status: :created, location: @payment }
  #     else
  #       format.html { render action: "new" }
  #       format.json { render json: @payment.errors, status: :unprocessable_entity }
  #     end
  #   end
  # end

  # PUT /payments/1
  # PUT /payments/1.json
  # def update
  #   @payment = Payment.find(params[:id])

  #   respond_to do |format|
  #     if @payment.update_attributes(params[:payment])
  #       format.html { redirect_to @payment, notice: 'Payment was successfully updated.' }
  #       format.json { head :no_content }
  #     else
  #       format.html { render action: "edit" }
  #       format.json { render json: @payment.errors, status: :unprocessable_entity }
  #     end
  #   end
  # end

  # DELETE /payments/1
  # DELETE /payments/1.json
  # def destroy
  #   @payment = Payment.find(params[:id])
  #   @payment.destroy

  #   respond_to do |format|
  #     format.html { redirect_to payments_url }
  #     format.json { head :no_content }
  #   end
  # end
end
