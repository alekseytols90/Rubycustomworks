# Copyright (c) 2016 Banff International Research Station.
# This file is part of Workshops. Workshops is licensed under
# the GNU Affero General Public License as published by the
# Free Software Foundation, version 3 of the License.
# See the COPYRIGHT file for details and exceptions.

require 'rails_helper'

describe 'RSVP', type: :feature do
  def reset_database
    Invitation.destroy_all
    Membership.destroy_all
    Person.destroy_all
    Event.destroy_all

    @event = create(:event, future: true)
    @person = create(:person, address1: '123 Street', city: 'City',
                     region: 'Region', postal_code: 'p0st4l', country: 'USA')
    @membership = create(:membership, event: @event, person: @person,
                         attendance: 'Invited')
    @invitation = create(:invitation, membership: @membership)
  end

  before do
    @lc = FakeLegacyConnector.new
    allow(LegacyConnector).to receive(:new).and_return(@lc)

    reset_database
  end

  before :each do
    visit rsvp_otp_path(@invitation.code)
  end

  it 'welcomes the user' do
    expect(current_path).to eq(rsvp_otp_path(@invitation.code))
    expect(page.body).to have_text("Dear #{@person.dear_name}:")
  end

  it 'displays the event name and date' do
    expect(page.body).to have_text(@event.name)
    expect(page.body).to have_text(@event.dates(:long))
  end

  it 'has yes, no, maybe buttons' do
    expect(page).to have_link('Yes')
    expect(page).to have_link('No')
    expect(page).to have_link('Maybe')
  end

  context 'Error conditions' do
    it 'past events' do
      @event.start_date = Date.today.last_year
      @event.end_date = Date.today.last_year + 5.days
      @event.save!

      visit rsvp_otp_path(@invitation.code)

      expect(page).to have_text('You cannot RSVP for past events')
    end

    it 'expired invitations' do
      @invitation.expires = Date.today.last_year
      @invitation.save

      visit rsvp_otp_path(@invitation.code)

      expect(page).to have_text('This invitation code is expired')
      @invitation.expires = Date.today.next_year
      @invitation.save
    end

    it 'non-existent invitations' do
      response = {'denied' => 'Invalid code'}
      lc = FakeLegacyConnector.new
      expect(LegacyConnector).to receive('new').and_return(lc)
      allow(lc).to receive('check_rsvp').and_return(response)

      visit rsvp_otp_path(123)

      expect(page).to have_text('Invalid code')
    end

    it 'participant not invited' do
      @membership.attendance = 'Not Yet Invited'
      @membership.save

      visit rsvp_otp_path(@invitation.code)

      expect(page).to have_text("The event's organizers have not yet
        invited you")
    end

    it 'participant already declined' do
      @membership.attendance = 'Declined'
      @membership.save

      visit rsvp_otp_path(@invitation.code)

      expect(page).to have_text("You have already declined an invitation")
    end
  end

  context 'User says No' do
    before do
      reset_database
    end

    it 'presents a "message to the organizer" form' do
      click_link 'No'
      expect(current_path).to eq(rsvp_no_path(@invitation.code))

      organizer_name = @event.organizer.name
      expect(page).to have_text(organizer_name)
      expect(page).to have_field("organizer_message")
    end

    it 'includes message in the organizer notice' do
      ActionMailer::Base.deliveries = []
      visit rsvp_no_path(@invitation.code)
      fill_in "organizer_message", with: 'A test message'
      click_button 'Decline Attendance'

      message_body = ActionMailer::Base.deliveries.last.body.raw_source
      expect(message_body).to include('A test message')
    end

    context 'after the "Decline Attendance" button' do
      before do
        ActionMailer::Base.deliveries = []
        visit rsvp_no_path(@invitation.code)
        click_button 'Decline Attendance'
      end

      it 'says thanks' do
        expect(page).to have_text('Thank you')
      end

      it 'declines membership' do
        expect(Membership.find(@membership.id).attendance).to eq('Declined')
      end

      it 'destroys invitation' do
        expect(Invitation.where(id: @invitation.id)).to be_empty
      end

      it 'notifies the event organizer' do
        expect(ActionMailer::Base.deliveries.count).not_to be_zero
        expect(ActionMailer::Base.deliveries.first.to).to include(@event.organizer.email)
      end

      it 'forwards to feedback form, with flash message' do
        expect(current_path).to eq(rsvp_feedback_path(@membership.id))
        expect(page.body).to have_css('div.alert.alert-success.flash',
          text: 'Your attendance status was successfully updated. Thanks for your reply!')
      end

      it 'updates legacy database' do
        lc = spy('lc')
        allow(LegacyConnector).to receive(:new).and_return(lc)

        reset_database
        visit rsvp_no_path(@invitation.code)
        click_button 'Decline Attendance'

        expect(lc).to have_received(:update_member).with(@membership)
      end
    end
  end

  context 'User says Maybe' do
    before do
      reset_database
      ActionMailer::Base.deliveries = []
      visit rsvp_otp_path(@invitation.code)
      click_link "Maybe"
    end

    it 'says thanks' do
      expect(page).to have_text('Thanks')
    end

    it 'displays invitation expiry date' do
      expect(page).to have_text(@invitation.expire_date)
    end

    it 'presents a "message to the organizer" form' do
      organizer_name = @event.organizer.name
      expect(page).to have_text(organizer_name)
      expect(page).to have_field("organizer_message")
    end

    it 'includes message in the organizer notice' do
      fill_in "organizer_message", with: 'A test message'
      click_button 'Send Reply'

      message_body = ActionMailer::Base.deliveries.first.body.raw_source
      expect(message_body).to include('A test message')
    end

    context 'after the "Send Reply" button' do
      before do
        reset_database
        ActionMailer::Base.deliveries = []
        visit rsvp_maybe_path(@invitation.code)
        click_button "Send Reply"
      end

      it 'changes membership attendance to Undecided' do
        expect(Membership.find(@membership.id).attendance).to eq('Undecided')
      end

      it 'notifies organizer' do
        expect(ActionMailer::Base.deliveries.count).not_to be_zero
        expect(ActionMailer::Base.deliveries.first.to).to include(@event.organizer.email)
      end

      it 'forwards to feedback form, with flash message' do
        expect(current_path).to eq(rsvp_feedback_path(@membership.id))
        expect(page.body).to have_css('div.alert.alert-success.flash',
          text: 'Your attendance status was successfully updated. Thanks for your reply!')
      end

      it 'updates legacy database' do
        lc = spy('lc')
        allow(LegacyConnector).to receive(:new).and_return(lc)

        reset_database
        visit rsvp_maybe_path(@invitation.code)
        click_button 'Send Reply'

        expect(lc).to have_received(:update_member).with(@membership)
      end
    end
  end

  context 'User says Yes' do
    before do
      reset_database
      @rsvp = RsvpForm.new(@invitation)
      visit rsvp_otp_path(@invitation.code)
      click_link "Yes"
    end

    it 'has arrival and departure date section' do
      expect(page).to have_text(@event.dates(:long))
      expect(page).to have_text(@rsvp.arrival_departure_intro)
    end

    it 'arrival & departure default to event start & end' do
      Capybara.ignore_hidden_elements = false
      arrival = page.find(:xpath, "//input[@id='arrival_date']").value
      departure = page.find(:xpath, "//input[@id='departure_date']").value

      expect(arrival).to eq(@event.start_date.strftime("%Y-%m-%d"))
      expect(departure).to eq(@event.end_date.strftime("%Y-%m-%d"))
    end

    it 'has guests form' do
      expect(page).to have_text(@rsvp.guests_intro)
      expect(page).to have_css('input#rsvp_membership_has_guest')
      expect(page).to have_css('input#rsvp_membership_guest_disclaimer')
    end

    it 'has special info/food form' do
      expect(page).to have_text(@rsvp.special_intro)
      expect(page).to have_css('textarea#rsvp_membership_special_info')
    end

    it 'has personal profile form' do
      expect(page).to have_text('Personal Information')
      expect(page).to have_field('rsvp_person_firstname')
      expect(page).to have_field('rsvp_person_lastname')
      expect(page).to have_field('rsvp_person_affiliation')
      expect(page).to have_field('rsvp_person_email')
      expect(page).to have_field('rsvp_person_url')
      expect(page).to have_field('rsvp_person_address1')
      expect(page).to have_field('rsvp_person_city')
      expect(page).to have_field('rsvp_person_region')
      expect(page).to have_field('rsvp_person_country')
      expect(page).to have_field('rsvp_person_biography')
      expect(page).to have_field('rsvp_person_research_areas')
    end

    it 'has privacy notice' do
      expect(page).to have_text(@rsvp.privacy_notice)
    end

    it 'has "message to the organizer" form' do
      organizer_name = @event.organizer.name
      expect(page).to have_text(organizer_name)
      expect(page).to have_field("organizer_message")
    end

    it 'includes message in the organizer notice' do
      ActionMailer::Base.deliveries = []
      fill_in "organizer_message", with: 'A test message'
      click_button 'Confirm Attendance'

      message_body = ActionMailer::Base.deliveries.first.body.raw_source
      expect(message_body).to include('A test message')
    end

    context 'after the "Confirm Attendance" button' do
      before do
        allow(SendParticipantConfirmationJob).to receive(:perform_later)
        visit rsvp_yes_path(@invitation.code)
        click_button 'Confirm Attendance'
      end

      it 'changes membership attendance to confirmed' do
        expect(Membership.find(@membership.id).attendance).to eq('Confirmed')
      end

      it 'sends notification email to organizer' do
        expect(ActionMailer::Base.deliveries.count).not_to be_zero
        expect(ActionMailer::Base.deliveries.first.to).to include(@event.organizer.email)
      end

      it 'sends confirmation email to participant via background job' do
        expect(SendParticipantConfirmationJob)
          .to have_received(:perform_later).with(@membership.id)
      end

      it 'destroys invitation' do
        expect(Invitation.where(id: @invitation.id)).to be_empty
      end

      it 'forwards to feedback form, with flash message' do
        expect(current_path).to eq(rsvp_feedback_path(@membership.id))
        expect(page.body).to have_css('div.alert.alert-success.flash',
          text: 'Your attendance status was successfully updated. Thanks for your reply!')
      end

      it 'updates legacy database' do
        lc = spy('lc')
        allow(LegacyConnector).to receive(:new).and_return(lc)

        reset_database
        visit rsvp_yes_path(@invitation.code)
        click_button 'Confirm Attendance'

        expect(lc).to have_received(:update_member).with(@membership)
      end
    end
  end

  context 'Feedback Form' do
    before :each do
      reset_database
      ActionMailer::Base.deliveries = []
      visit rsvp_feedback_path(@invitation.membership_id)
    end

    def fill_in_feedback_from(msg)
      fill_in 'feedback_message', with: msg
      click_button 'Send Feedback'
    end

    it 'sends feedback email if user enters feedback text' do
      fill_in_feedback_from('Testing feedback form')

      message_body = ActionMailer::Base.deliveries.first.body.raw_source
      expect(message_body).to include('Testing feedback form')
    end

    it 'forwards to event membership page, with flash message' do
      fill_in_feedback_from('Test')

      url = event_memberships_path(@invitation.membership.event)
      expect(current_path).to eq(url)
      expect(page.body).to have_css('div.alert.alert-success.flash',
        text: 'Thanks for the feedback!')
    end

    it 'does not send email if no text is entered' do
      fill_in_feedback_from('')
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end
end
