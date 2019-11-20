# Copyright (c) 2016 Banff International Research Station.
# This file is part of Workshops. Workshops is licensed under
# the GNU Affero General Public License as published by the
# Free Software Foundation, version 3 of the License.
# See the COPYRIGHT file for details and exceptions.

# Helpers for memberships
module MembershipsHelper

  def pending_invitation?
    @current_user.person == @membership.person && !@membership.invitation.nil?
  end

  def event_membership_name(m)
    m.event.code + ': ' + m.event.name + ' (' + m.event.date + ')'
  end

  def date_list
    start_date = @event.start_date
    end_date = @event.end_date
    if policy(@membership).extended_stay?
      start_date -= 7.days
      end_date += 7.days
    end
    dates = [start_date]
    dates << dates.last + 1.day while dates.last != end_date
    dates
  end

  def selected_date(type = nil)
    if type == 'arrival'
      return @membership.arrival_date unless @membership.arrival_date.nil?
      return @event.start_date
    else
      return @membership.departure_date unless @membership.departure_date.nil?
      return @event.end_date
    end
  end

  def show_roles(f, default: nil)
    disabled_options = []
    if @current_user.is_organizer?(@event) && !@current_user.is_admin?
      disabled_options = ['Contact Organizer', 'Organizer']
    end

    f.select :role, Membership::ROLES,
             { disabled: disabled_options, selected: default },
             class: 'form-control'
  end

  def add_member_errors(add_members)
    return '' if add_members.errors.empty?
    errors = add_members.errors
    msg = "<p><strong>‼️These problems were detected:</strong>\n"
    msg << "<ol id=\"add-members-errors\">\n"
    errors.messages.each do |line|
      msg << "<li value=\"#{line[0]}\">"
      line[1].each do |prob|
        msg << "#{prob}, "
      end
      msg.chomp!(', ') << ".</li>\n"
    end
    msg << "</ol>\n"

    msg << '</p>'
  end

  def show_attendances(f)
    if policy(@membership).edit_attendance?
      f.select :attendance, policy(@membership).attendance_options,
                { selected: @membership.attendance }, class: 'form-control'
    else
      @membership.attendance
    end
  end

  def print_section?(section)
    return ' no-print' unless section == 'Confirmed'
  end

  def invite_title(status)
    title = 'Send '
    title << (status == 'Not Yet Invited' ? 'Invitations ' : 'Reminders ')
    title << 'to ' + status + ' Members'
  end

  def format_invited_by(membership)
    invited_by=''
    unless membership.invited_by.blank?
      invited_by = membership.invited_by
      unless membership.invited_on.blank?
        invited_by << ' on <br>'
        tz = membership.event.time_zone
        invited_by << membership.invited_on.in_time_zone(tz).to_s
      end
    end
    invited_by
  end

  def show_invited_by?
    invited_by = ''
    unless ['Confirmed', 'Not Yet Invited'].include? @membership.attendance
      invited_by = '<div class="row" id="profile-rsvp-invited">Invited by: '
      invited_by << format_invited_by(@membership)
      invited_by << '</div>'
    end
    invited_by.html_safe
  end

  def rsvp_by(event_start, invited_on)
    rsvp_by = RsvpDeadline.new(event_start, invited_on).rsvp_by
    DateTime.parse(rsvp_by).strftime('%b. %e, %Y')
  end

  def parse_reminders(member)
    tz = member.event.time_zone

    text = '<ul>'
    member.invite_reminders.each do |k,v|
      start_date = member.event.start_date.in_time_zone(tz)
      reply_by = rsvp_by(start_date, k.in_time_zone(tz))
      text << "<li><b>On #{k.strftime('%Y-%m-%d %H:%M %Z')}</b><br>by #{v}.<br>
              &nbsp;&nbsp;&bull; Reply-by: #{reply_by}</li>".squish
    end
    text << '</ul>'
  end

  def show_reply_by_date(member)
    tz = member.event.time_zone
    start_date = member.event.start_date.in_time_zone(tz)
    invited_on = member.invited_on.blank? ? DateTime.current.in_time_zone(tz) :
                  member.invited_on.in_time_zone(tz)
    DateTime.parse(rsvp_by(start_date, invited_on)).strftime("%Y-%m-%d")
  end

  def show_invited_on_date(member)
    column = '<td class="rowlink-skip no-print">'
    if show_invited_on?(member)
      if member.invited_on.blank?
        column << '(not set)'
      else
        tz = member.event.time_zone
        start_date = member.event.start_date.in_time_zone(tz)
        invited_on = member.invited_on.in_time_zone(tz)
        column << '<a class="invitation-dates" tabindex="0" title="Invitation Sent"
          role="button" data-toggle="popover" data-placement="top" data-html="true"
          data-target="#invitations-' + member.id.to_s + '"
          data-trigger="hover focus" data-content="By ' +
          format_invited_by(member) + '<br><b>Reply-by date:</b> ' +
          rsvp_by(start_date, invited_on) +
          '" >'+ member.invited_on.strftime("%Y-%m-%d") +'</a>'
      end
      unless member.invite_reminders.blank?
        column << ' <span id="reminders-icon"><a tabindex="0" title="Reminders Sent" role="button" data-toggle="popover" data-html="true" data-target="#reminders-' + member.id.to_s + '" data-trigger="hover focus" data-content="' + parse_reminders(member) + '"> &nbsp; <i class="fa fa-md fa-repeat"></i></a></span>'.html_safe
      end
    end
    column << '</td>'
    column.html_safe
  end

  def show_invited_on?(member)
    policy(@event).send_invitations? &&
      %w(Invited Undecided).include?(member.attendance)
  end

  def add_email_buttons(status)
    return unless policy(@event).show_email_buttons?(status)
    content = '<div class="no-print" id="email-members">'
    content << add_email_button(status)
    content << "\n</div>\n"
    content.html_safe
  end

  def invite_button(status, smallscreen = false)
    return 'Invite Selected Members' if status == 'Not Yet Invited'
    return 'Send Reminders to Selected' if smallscreen
    "Send Reminder to Selected #{status.titleize} Members"
  end

  def spots_left
    @event.max_participants - @event.num_invited_participants > 0
  end

  def add_email_button(status)
    return '' unless policy(@event).show_email_buttons?(status)
    to_email = "#{@event.code}-#{status.parameterize(separator: '_')}@#{@domain}"
    to_email = "#{@event.code}@#{@domain}" if status == 'Confirmed'
    content = mail_to(to_email, "<i class=\"fa fa-envelope fa-fw\"></i> Email #{status} Members".html_safe, subject: "[#{@event.code}] ", title: "Email #{to_email}", class: "btn btn-primary email-members")

    if status == 'Confirmed' && !@organizer_emails.blank?
      content << ' | '
      content << mail_to(@organizer_emails.join(','), "<i class=\"fa fa-envelope fa-fw\"></i> Email Organizers".html_safe, subject: "[#{@event.code}] ", class: 'btn btn-primary email-members')
    end
    content
  end

  def show_email(member)
    column = ''
    if policy(member).show_email_address?
      column = '<td class="hidden-md hidden-lg rowlink-skip no-print" align="middle">' +
        mail_to(member.person.email, '<span class="glyphicon glyphicon-envelope"></span>'.html_safe,
          title: "#{member.person.email}", subject: "[#{@event.code}] ") +
          '</td><td class="hidden-xs hidden-sm rowlink-skip no-print">' +
          mail_to(member.person.email, member.person.email, subject: "[#{@event.code}] ") +
          '</td>'
    elsif policy(member).use_email_addresses?
          column = '<td class="hidden-md hidden-lg rowlink-skip no-print" align="middle">' +
            mail_to(member.person.email, '<span class="glyphicon glyphicon-lock"></span>'.html_safe, :title => "E-mail not shared with other members", subject: "[#{@event.code}] ") +
            '</td><td class="hidden-xs hidden-sm rowlink-skip no-print">' +
            mail_to(member.person.email, '[not shared]', title: "E-mail not shared with other members", subject: "[#{@event.code}] ") +
            '</td>'
    elsif policy(member).show_not_shared?
      column = '<td class="hidden-md hidden-lg rowlink-skip no-print" align="middle">' +
        '<a title="E-mail not shared" class="glyphicon glyphicon-lock"></a></td>' +
        '<td class="hidden-xs hidden-sm rowlink-skip">[not shared]</td>'
    end
    column.html_safe
  end

  def add_limits_message
    invited = @event.num_invited_participants
    spots = @event.max_participants - invited
    isare = 'are'
    isare = 'is' if spots == 1
    spot_s = 'spots'
    spot_s = 'spot' if spots == 1
    unless_cancel = ''
    if spots == 0
      unless_cancel = "<br>\nUnless someone cancels, no more invitations can be sent."
    end
    ('<div class="no-print" id="limits-message">There ' + "#{isare} #{spots} #{spot_s} left:
      #{invited} confirmed & invited / #{@event.max_participants} maximum. #{unless_cancel}</div>").squish.html_safe
  end

  def display_new_feature_notice?
    @unread_notice && @current_user.sign_in_count > 1 &&
      Date.current < Date.parse('2019-11-30') && policy(@event).send_invitations?
  end
end
