load "nick_reporting/test_data.rb"
load "nick_reporting/access_reports/access_report_methods.rb"
load "nick_reporting/company_users.rb"

start = ARGV[0].to_date.beginning_of_day
if ARGV[6] == "stub"
    if start.day <= 15
        report_start = start.beginning_of_month
    else
        report_start = start.beginning_of_month + 1.months
    end
else
    report_start = start
end
@quarters = [
  {label: 1, min: start, max: (report_start + 3.months - 1.days).end_of_day},
  {label: 2, min: (report_start + 3.months).beginning_of_day, max: (report_start + 6.months - 1.days).end_of_day},
  {label: 3, min: (report_start + 6.months).beginning_of_day, max: (report_start + 9.months - 1.days).end_of_day},
  {label: 4, min: (report_start + 9.months).beginning_of_day, max: (report_start + 12.months - 1.days).end_of_day}
]
if ARGV[1] == "0"
    stop = @quarters[quarter - 1][:max]
else
    stop = ARGV[1].to_date.end_of_day
end
quarter = ARGV[2].to_i
id = Company.
      where.not(suspended_yn: true).
      find_by(name: ARGV[3]).
      id
contract_start = Company.find(id).contract_detail.contract_start.beginning_of_day
years_since_start = get_age(stop, contract_start)
if years_since_start > 0
    if contract_start.day <= 15
        contract_year_start = contract_start.beginning_of_month + years_since_start.years
    else
        contract_year_start = contract_start.beginning_of_month + 1.months + years_since_start.years
    end
else
    contract_year_start = contract_start
end

total_onboarded = Company.
                  find(id).
                  user_companies.
                  where.not(
                      deleted_yn: true,
                      user_id: @test).
                  distinct.
                  pluck(:user_id)

#1) Number of unique users accessing sessions
#Have to be "used up" - completed, late cancelled or absent
#We'll copy this for counsellors later
completed_sessions =    Appointment.
                        completed.
                        joins(:users).
                        where(
                            client_covered_yn: true,
                            users: {id: total_onboarded}).
                        where("start_date BETWEEN ? AND ?", contract_year_start, stop).
                        where.not(id: @testapp).
                        distinct.
                        pluck(:id)
late_cancel_sessions =  Cancellation.
                        joins(:appointment).
                        where(
                            user_id: total_onboarded,
                            appointments: {client_covered_yn: true}).
                        where("EXTRACT (EPOCH FROM start_date - cancellations.created_at) < 43200").
                        where("start_date BETWEEN ? AND ?", contract_year_start, stop).
                        where.not(appointment_id: @testapp).
                        distinct.
                        pluck(:appointment_id)         
absent_counselling_sessions =   AppointmentAbsence.
                                joins(:appointment).
                                where(
                                    user_id: total_onboarded,
                                    appointments: {client_covered_yn: true}).
                                    where("start_date BETWEEN ? AND ?", contract_year_start, stop).  
                                where.not(appointment_id: @testapp).
                                distinct.
                                pluck(:appointment_id)
all_sessions = completed_sessions + late_cancel_sessions + absent_counselling_sessions
first_range_access_users =  Appointment.
                            joins(:users).
                            where(
                                id: all_sessions,
                                users: {id: total_onboarded}
                                ).
                            group("users.id").
                            having("MIN(start_date) BETWEEN ? AND ?", start, stop).
                            pluck("users.id", "MIN(start_date)").to_h
first_all_time_access_users =   Appointment.
                                joins(:users).
                                where(
                                    id: all_sessions,
                                    users: {id: total_onboarded}
                                    ).
                                where("start_date <= ?", stop).
                                group("users.id"). 
                                pluck("users.id", "MIN(start_date)").to_h

#Users accessing paid sessions
coverage_users =  CompanyUsedMinute.
            joins(:appointment).
            where.not(
                deleted_yn: true,
                appointment_id: @testapp).
            where(
                company_id: id,
                user_id: total_onboarded).
            group(:user_id).
            having("MIN(start_date) BETWEEN ? AND ?", start, stop).
            pluck(:user_id, "MIN(start_date)").to_h

sale_users =  Appointment.
        joins(:payments).
        where(
            client_covered_yn: true,
            payments: {
                user_id: total_onboarded, 
                payment_type: "sale",
                refund_id: nil}).
        where.not(
            id: @testapp,
            payments: {transaction_id: nil}).
        group(:user_id).
        having("MIN(start_date) BETWEEN ? AND ?", start, stop).
        pluck(:user_id, "MIN(start_date)").to_h

first_paid_users = coverage_users.merge(sale_users) {|key, oldval, newval| [newval, oldval].min}

quarter_users = [[], [], [], []]

first_range_access_users.each do |user, date|
    temp_quarter = get_quarter(date)
    if temp_quarter
        quarter_users[temp_quarter-1] << user
    end
end

quarter_users_count = []
for i in 0..3
    quarter_users_count << quarter_users[i].size
end

quarter_paid_users = [[], [], [], []]

first_paid_users.each do |user, date|
    temp_quarter = get_quarter(date)
    if temp_quarter
        quarter_paid_users[temp_quarter-1] << user
    end
end
  
quarter_paid_users_count = []
for i in 0..3
    quarter_paid_users_count << quarter_paid_users[i].size
end

workplace_stress_coding = {
        "High Workload": {assess_codes: "work_demand", direction: "negative", match_codes: "work1", type: "both"},
        "Lack of Control": {assess_codes: "work_influence", direction: "positive", match_codes: "work2", type: "both"},
        "Poor Management": {assess_codes: ["work_theytrust", "work_youtrust"], direction: "positive", match_codes: "work6", type: "both"},
        "High Conflict": {assess_codes: ["work_conflict", "work_relationship"], direction: "positive", match_codes: "work7", type: "both"},
        "Job Uncertainty": {assess_codes: "work_security", direction: "positive", match_codes: "work8", type: "both"},
        "Work-Life Balance": {assess_codes: "work_balance", direction: "negative", match_codes: "work9", type: "both"},
        "Harassment": {assess_codes: ["work_bully", "work_sex"], direction: "negative", match_codes: ["work10", "work11"], type: "both"},
        "Discrimination": {assess_codes: nil, direction: nil, match_codes: ["work12", "work13"], type: "match"},
        "Not Appreciated": {assess_codes: nil, direction: nil, match_codes: ["work4"], type: "match"},
        "Unfair Treatment": {assess_codes: "work_fairness", direction: "negative", match_codes: "work5", type: "both"},
        "Not Meaningful": {assess_codes: "work_meaningful", direction: "negative", match_codes: "work3", type: "both"}
}

personal_stress_coding = {
    "Stress": {assess_codes: ['dass3', 'dass7'], direction: "negative", match_codes: {present_codes: nil, int_codes: ['dass3', 'dass7']}, type: "both"},
    "Depression":  {assess_codes: ['dass1', 'dass5'], direction: "negative", match_codes: {present_codes: ['dx1', 'dx4'], int_codes: ['dass1', 'dass5']}, type: "both"},
    "Anxiety":  {assess_codes: ['dass2', 'dass6'], direction: "negative", match_codes: {present_codes: 'dx2', int_codes: ['dass2', 'dass6']}, type: "both"},
    "Grief & Loss":  {assess_codes: nil, direction: nil, match_codes: {present_codes: 'stress4', int_codes: nil}, type: "match"},
    "Loneliness":  {assess_codes: nil, direction: nil, match_codes: {present_codes: 'stress1', int_codes: nil}, type: "match"},
    "Personal": {assess_codes: nil, direction: nil, match_codes: {present_codes: ['stress7', 'stress8', 'stress15', 'stress16'], int_codes: nil}, type: "match"},
    "Substance Use": {assess_codes: ['dass4'], direction: "negative", match_codes: {present_codes: ['dx3'], int_codes: ['dass4']}, type: "both"},
    "Trauma": {assess_codes: nil, direction: nil, match_codes: {present_codes: 'dx10', int_codes: nil}, type: "match"},
    "Abuse": {assess_codes: nil, direction: nil, match_codes: {present_codes: 'stress9', int_codes: nil}, type: "match"},
    "Marital/relationships": {assess_codes: nil, direction: nil, match_codes: {present_codes: 'stress2', int_codes: nil}, type: "match"},
    "Family": {assess_codes: nil, direction: nil, match_codes: {present_codes: ['stress3', 'stress5'], int_codes: nil}, type: "match"}, 
    "Health": {assess_codes: nil, direction: nil, match_codes: {present_codes: ['stress6', 'stress17'], int_codes: nil}, type: "match"},
    "Financial": {assess_codes: nil, direction: nil, match_codes: {present_codes: 'stress10', int_codes: nil}, type: "match"},
    "Legal": {assess_codes: nil, direction: nil, match_codes: {present_codes: 'stress11', int_codes: nil}, type: "match"},
    "Parenting": {assess_codes: nil, direction: nil, match_codes: {present_codes: 'stress12', int_codes: nil}, type: "match"}
}

deps = CompanyDependant.
        where.not(user_id: @test).
        pluck(:user_id)
if ARGV[4] == "large"
    quarter_status = []
    quarter_gender = []
    quarter_age = []
    quarter_gen = []
    quarter_personal_stressors = []
    quarter_workplace_stressors = []
    quarter_custom1 = []
    quarter_custom2 = []
    quarter_custom3 = []
    quarter_custom4 = []
    for i in 1..quarter
        users = quarter_users[i-1]
        quarter_status << get_quarter_status(users, deps, id)
        quarter_gender << get_quarter_gender(users)
        quarter_age << get_quarter_age(users, first_range_access_users)
        quarter_gen << get_quarter_gen(users)
        quarter_personal_stressors << generate_personal_stressors(users, personal_stress_coding, first_range_access_users)
        quarter_workplace_stressors << generate_workplace_stressors(users, workplace_stress_coding, first_range_access_users)
        quarter_custom1 << get_custom_fields(users, 1)
        quarter_custom2 << get_custom_fields(users, 2)
        quarter_custom3 << get_custom_fields(users, 3)
        quarter_custom4 << get_custom_fields(users, 4)
    end
else
    ytd_users = quarter_users.flatten
    quarter_status = get_quarter_status(ytd_users, deps, id)
    quarter_gender = get_quarter_gender(ytd_users)
    quarter_age = get_quarter_age(ytd_users, first_range_access_users) #I found a faster but more complicated way to do it that I'm going to try to implement later but it requires making temporary tables to run rails queries
    quarter_gen = get_quarter_gen(ytd_users)
    quarter_personal_stressors = generate_personal_stressors(ytd_users, personal_stress_coding, first_range_access_users).sort_by{ |issue, count| [-count, issue] }.to_h
    quarter_workplace_stressors = generate_workplace_stressors(ytd_users, workplace_stress_coding, first_range_access_users).sort_by{ |issue, count| [-count, issue] }.to_h
    quarter_custom1 = get_custom_fields(ytd_users, 1)
end

#Usage
#Number using full allotment
if ARGV[5] == "plus"
    user_types = {}
    user_types[:"employee"] = total_onboarded - deps
    user_types[:"dependant"] = total_onboarded & deps

    employee_bite_limit = Company.find(id).company_minute.video_bite_employee_minutes
    employee_access_limit = Company.find(id).company_minute.video_access_employee_minutes
    dependant_bite_limit = Company.find(id).company_minute.video_bite_dependant_minutes
    dependant_access_limit = Company.find(id).company_minute.video_access_dependant_minutes

    employee_full_bite = accessed_coverage_limit(user_types[:employee], "bite", employee_bite_limit, contract_year_start, stop)
    employee_full_access = accessed_coverage_limit(user_types[:employee], "access", employee_access_limit, contract_year_start, stop)
    dependant_full_bite = accessed_coverage_limit(user_types[:dependant], "bite", dependant_bite_limit, contract_year_start, stop)
    dependant_full_access = accessed_coverage_limit(user_types[:dependant], "access", dependant_access_limit, contract_year_start, stop)
end

#This uses start instead of contract_start. So it can be misaligned
#If contract start is within range, it could seem like someone is using more hours without hitting limit
#If contract start is before range, it could seem like someone is hitting limit with fewer hours
#Bite usage
bite =  CompanyUsedMinute.
        joins(:appointment).
        where.not(
                deleted_yn: true,
                appointment_id: @testapp).
            where(
                minute_type: "bite",
                company_id: id).
            where("appointments.start_date BETWEEN ? AND ?", start, stop).
            pluck("SUM(minutes)")[0].to_f / 60

#Access usage
access =    CompanyUsedMinute.
            joins(:appointment).
            where.not(
                minute_type: "bite",
                deleted_yn: true,
                appointment_id: @testapp).
            where(company_id: id).
            where("appointments.start_date BETWEEN ? AND ?", start, stop).
            pluck("SUM(minutes)")[0].to_f / 60

#Sale usage
sale =  Appointment.
        joins(:payments).
        where(
            client_covered_yn: true,
            payments: {
                user_id: total_onboarded, 
                payment_type: "sale",
                refund_id: nil}).
        where("appointments.start_date BETWEEN ? AND ?", start, stop).
        where.not(
            id: @testapp,
            payments: {transaction_id: nil}).
        pluck("SUM(amount) / 75")[0].to_f
#This assumes everyone pays $75/hour, but the reality is some people have discounts or different pricing. 

#ORS
#The first completed match for any given user
first_matches = Match.
                joins(:users).
                where(
                    completed_yn: true, 
                    users: {id: first_all_time_access_users.keys}).
                where.not(users: {id: @test}).
                group("users.id").
                pluck("users.id", "MIN(matches.id)").to_h

#Users with three or more completed appointments before stop date
three_app_users =   Appointment.
                    completed.
                    joins(:users).
                    where("start_date <= ?", stop).
                    where(  client_covered_yn: true,
                            users: {id: first_matches.keys}).
                    where.not(id: @testapp).
                    group("users.id").
                    having("COUNT(*) >= 3").
                    pluck("users.id")

#Filter out pre-session assessments that are all 5s
pre_session_ors_answers =   AssessmentMetric.
                            where(name: ["Individual", "Interpersonal", "Social", "Overall"]).
                            where(assessment_type_id: 3).
                            pluck(:id)
real_ass =  AssessmentScore.
            joins(assessment: :appointment).
            where("start_date < ?", stop).
            where(assessment_metric_id: pre_session_ors_answers).
            where.not(
                value: 5,
                appointments: {id: @testsapp}).
            distinct.
            pluck(:assessment_id)

#Find the valid assessment associated with the user's third appointment, or most recent after that if not available (up to 5th).
valid_user_apps = {}
three_app_users.each do |user|
    apps =  User.
            find(user).
            appointments.
            completed.
            where("start_date < ?", stop).
            where.not(appointments: {id: @testapp}).
            order(:start_date)
    for i in 2..4
        assessment_id = apps[i]&.
                        assessments&.
                        find_by_assessment_type_id(3)&.
                        id
        if real_ass.include?(assessment_id)
            valid_user_apps[user] = assessment_id
            break
        end 
    end
end

new_ors_answer_ids = Array(1..20)
initial = 0.to_f
total = 0.to_f
count = 0.to_f
#ors_check = {}
valid_user_apps.each do |user, ass_id|
    last =  Assessment.
            find(ass_id).
            assessment_scores.
            where(assessment_metric_id: pre_session_ors_answers).
            pluck("AVG(value)")[0].to_f
    match_id = first_matches[user]
    match_type =    Match.
                    find(match_id).
                    match_type
    if match_type == "legacy"
        scores =    User.
                    find(user).
                    assessments.
                    find_by(assessment_type_id: 1).
                    assessment_scores.
                    pluck(:value)
        first_session_scores =  User.
                                find(user).
                                appointments.
                                completed.
                                where.not(id: @testapp).
                                order(:start_date).
                                first.
                                assessments.
                                find_by_assessment_type_id(3).
                                assessment_scores.
                                pluck(:value)
        scores_check = nil
        first_scores_check = nil         
        if scores.uniq != [5]
            scores_check = scores.sum.to_f / scores.size
        end
        if first_session_scores.uniq != [5]
            first_scores_check = first_session_scores.sum.to_f / first_session_scores.size
        end
        first = [scores_check, first_scores_check].compact.min
        if first.nil?
            next
        end
    elsif ["express", "comprehensive"].include?(match_type)
        first = UserAnswer.
                joins(:match_answer).
                where(match_id: match_id).
                where(match_answer_id: new_ors_answer_ids).
                pluck("AVG(CAST (value as INT) - 1) * 2.5")[0].to_f    
    end
=begin
    ors_check[user] = {}
    ors_check[user][:initial] = first
    ors_check[user][:last] = last
    ors_check[user][:change] = last - first
=end
    initial += first
    total = total + last.to_f - first.to_f
    count += 1
end
ors = {count: count, initial: initial/count, change: total/count, percent: "#{(total/initial * 100).round(2)}%"}

#User satisfaction:
#List of appropriate metrics from post-session questionnaire
srs_metrics =   AssessmentMetric.
                where(assessment_type: AssessmentType.find_by_name("Post")).
                where(name: ["Therapist Relationship", "Goals and Topics", "Approach or Method", "Overall"]).
                pluck(:id)

#Filter for valid assessments from the relevant users
real_post_session = Assessment.
                    joins(:assessment_scores, :appointment).
                    where.not(appointment_id: @testapp).
                    where("start_date <= ?", stop).
                    where(
                        assessment_scores: {assessment_metric_id: srs_metrics},
                        user_id: first_all_time_access_users.keys).
                    where("value != 5").
                    distinct.
                    pluck(:id)
#Just list of users so we can loop through them
real_post_users =   Assessment.
                    where(id: real_post_session).
                    distinct.
                    pluck(:user_id)

total = 0.to_f
count = 0.to_f

#post_check = {}
real_post_users.each do |user|
    average_srs =   User.
                    find(user).
                    assessments.where(id: real_post_session).
                    joins(:assessment_scores).
                    where(assessment_scores: {assessment_metric_id: srs_metrics}).
                    pluck("AVG(value)")[0].to_f
=begin
    #For checking individual users
    post_check[user] = {}
    post_check[user][:srs] = average_srs
    post_check[user][:count] = User.find(user).assessments.where(id: real_post_session).size
=end
    total += average_srs
    count += 1    
end

first = Assessment.
        where(id: real_post_session).
        joins(:assessment_scores).
        pluck("AVG(value)")[0].to_f
second = total/count
srs = (first + second)/2

if ARGV[7] == "hash"
    final_hash = {}
    final_hash[:"quarter_users"] = quarter_users_count
    final_hash[:"quarter_paid_users"] = quarter_paid_users_count
    final_hash[:"quarter_status"] = quarter_status
    final_hash[:"quarter_gender"] = quarter_gender
    final_hash[:"quarter_age"] = quarter_age
    final_hash[:"quarter_gen"] = quarter_gen
    final_hash[:"quarter_personal_stressors"] = quarter_personal_stressors
    final_hash[:"quarter_workplace_stressors"] = quarter_workplace_stressors
    final_hash[:"quarter_custom1"] = quarter_custom1
    if ARGV[4] == "large"
        final_hash[:"quarter_custom2"] = quarter_custom2
        final_hash[:"quarter_custom3"] = quarter_custom3
        final_hash[:"quarter_custom4"] = quarter_custom4
    end
    final_hash[:"total_users"] = company_users(start, stop, ARGV[3]).size
    if ARGV[5] == "plus"
        final_hash[:"full_allotment"] = {}
        final_hash[:"full_allotment"][:"employee"] = {} 
        final_hash[:"full_allotment"][:"employee"][:"bite"] = employee_full_bite
        final_hash[:"full_allotment"][:"employee"][:"access"] = employee_full_access
        final_hash[:"full_allotment"][:"employee"][:"count"] = employee_full_access + employee_full_bite
        final_hash[:"full_allotment"][:"dependant"] = {}
        final_hash[:"full_allotment"][:"dependant"][:"bite"] = dependant_full_bite
        final_hash[:"full_allotment"][:"dependant"][:"access"] = dependant_full_access
        final_hash[:"full_allotment"][:"dependant"][:"count"] = dependant_full_access + dependant_full_bite
    end
    final_hash[:"allotment_usage"] = {}
    final_hash[:"allotment_usage"][:"bite"] = bite
    final_hash[:"allotment_usage"][:"access"] = access
    final_hash[:"allotment_usage"][:"sale"] = sale
    final_hash[:"allotment_usage"][:"total"] = bite + access + sale

    final_hash[:"average_hours_per_user"] = (bite + access + sale)/first_range_access_users.size
    final_hash[:"ors"] = ors
    final_hash[:"srs"] = srs

    pp final_hash
elsif ARGV[7] == "csv"
    require "csv"
    CSV.open("#{Rails.root.join('tmp').to_s}/access_report.csv", 'w') do |writer|
        writer << [ARGV[3]]
        writer << ["Start of contract year", contract_year_start]
        writer << ["Report Dates", "#{start.year}-#{start.month}-#{start.day} - #{stop.year}-#{stop.month}-#{stop.day}"]
        writer << ["Title Dates", "#{report_start.year}-#{report_start.month}-#{report_start.day} - #{stop.year}-#{stop.month}-#{stop.day}"]
        writer << ["Group", "Q1", "Q2", "Q3", "Q4"]
        writer << ["Accessing Users", quarter_users_count].flatten
        writer << ["Paid Users",quarter_paid_users_count].flatten
        writer << ["Status"]
        array_from_hash(normalize_hash(quarter_status)).each do |metric|
            writer << metric
        end
        writer << ["Gender"]
        array_from_hash(normalize_hash(quarter_gender)).each do |metric|
            writer << metric
        end
        writer << ["Age"]
        array_from_hash(quarter_age).each do |metric|
            writer << metric
        end
        writer << ["Generation"]
        array_from_hash(quarter_gen).each do |metric|
            writer << metric
        end
        writer << ["Custom1"]
        array_from_hash(normalize_hash(quarter_custom1)).each do |metric|
            writer << metric
        end
        if ARGV[4] == "large"
            writer << ["Custom2"]
            array_from_hash(normalize_hash(quarter_custom2)).each do |metric|
                writer << metric
            end
            writer << ["Custom3"]
            array_from_hash(normalize_hash(quarter_custom3)).each do |metric|
                writer << metric
            end
            writer << ["Custom4"]
            array_from_hash(normalize_hash(quarter_custom4)).each do |metric|
                writer << metric
            end
        end
        writer << ["Total Population", company_users(start, stop, ARGV[3]).size]
        writer << ["Personal Stressors"]
        array_from_hash(quarter_personal_stressors).each do |metric|
            writer << metric
        end
        writer << ["Workplace Stressors"]
        array_from_hash(quarter_workplace_stressors).each do |metric|
            writer << metric
        end
        if ARGV[5] == "plus"
            writer << ["Employees accessing full bite", employee_full_bite]
            writer << ["Employees accessing full access", employee_full_access]
            writer << ["Dependants accessing full bite", dependant_full_bite]
            writer << ["Dependants accessing full access", dependant_full_access]
        end
        writer << ["Total", bite + access + sale]
        writer << ["Bite usage", bite]
        writer << ["Access usage", access]
        writer << ["Sale usage", sale]
        writer << ["Average hours per user", (bite + access + sale)/first_range_access_users.size]
        writer << ["ors", ors[:percent]]
        writer << ["srs", srs] 
    end
else
    puts "Choose a valid data format to output: hash or csv"
end

#cd Downloads
#rsync -azP --stats deploy@162.248.180.58:/data/web/api.inkblotpractice.com/current/tmp/access_report.csv .
#rsync -azP --stats deploy-inkblot-us-prod-1.medstack.net:~/medapi.inkblottherapy.com/current/tmp/access_report.csv .
