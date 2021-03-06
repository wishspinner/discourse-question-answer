module TopicQAExtension
  def reload(options = nil)
    @answers = nil
    @comments = nil
    @last_answerer = nil
    super(options)
  end

  def answers
    @answers ||= posts.where(reply_to_post_number: [nil, '']).order("created_at ASC")
  end

  def comments
    @comments ||= posts.where.not(reply_to_post_number: [nil, '']).order("created_at ASC")
  end

  def answer_count
    answers.count - 1 ## minus first post
  end

  def comment_count
    comments.count
  end

  def last_answered_at
    if answers.any?
      answers.last[:created_at]
    else
      nil
    end
  end

  def last_commented_on
    if comments.any?
      comments.last[:created_at]
    else
      nil
    end
  end

  def last_answer_post_number
    if answers.any?
      answers.last[:post_number]
    else
      nil
    end
  end

  def last_answerer
    if answers.any?
      @last_answerer ||= ::User.find(answers.last[:user_id])
    else
      nil
    end
  end
end

require_dependency 'topic'
class ::Topic
  prepend TopicQAExtension

  def self.voted(topic, user)
    return nil if !user || !SiteSetting.qa_enabled

    PostCustomField.exists?(post_id: topic.posts.map(&:id),
                            name: 'voted',
                            value: user.id)
  end

  def self.qa_enabled(topic)
    return false if !SiteSetting.qa_enabled
    return false if !topic || !topic.respond_to?(:is_category_topic?) || topic.is_category_topic?

    tags = topic.tags.map(&:name)
    has_qa_tag = !(tags & SiteSetting.qa_tags.split('|')).empty?
    is_qa_category = topic.category && topic.category.custom_fields["qa_enabled"]
    is_qa_subtype = topic.subtype == 'question'

    has_qa_tag || is_qa_category || is_qa_subtype
  end

  def self.update_vote_order(topic_id)
    return if !SiteSetting.qa_enabled

    posts = Post.where(topic_id: topic_id)

    posts.where(post_number: 1).update(sort_order: 1)

    answers = posts.where(reply_to_post_number: [nil, ''])
      .where.not(post_number: 1)
      .order("(
        SELECT COALESCE ((
          SELECT value::integer FROM post_custom_fields
          WHERE post_id = posts.id AND name = 'vote_count'
        ), 0)
      ) DESC, post_number ASC")

    count = 2
    answers.each do |a|
      a.update(sort_order: count)
      comments = posts.where(reply_to_post_number: a.post_number)
        .order("post_number ASC")
      if comments.any?
        comments.each do |c|
          count += 1
          c.update(sort_order: count)
        end
      else
        count += 1
      end
    end
  end
end

module TopicViewQAExtension
  def qa_enabled
    ::Topic.qa_enabled(@topic)
  end

  def filter_posts_by_ids(post_ids)
    if qa_enabled
      posts = ::Post.where(id: post_ids, topic_id: @topic.id)
        .includes(:user, :reply_to_user, :incoming_email)
      @posts = posts.order("case when post_number = 1 then 0 else 1 end, sort_order ASC")
      @posts = filter_post_types(@posts)
      @posts = @posts.with_deleted if @guardian.can_see_deleted_posts?
      @posts
    else
      super
    end
  end
end

class TopicView
  prepend TopicViewQAExtension
end

require_dependency 'topic_view_serializer'
require_dependency 'basic_user_serializer'
class ::TopicViewSerializer
  attributes :qa_enabled,
             :voted,
             :last_answered_at,
             :last_commented_on,
             :answer_count,
             :comment_count,
             :last_answer_post_number,
             :last_answerer

  def qa_enabled
    object.qa_enabled
  end

  def voted
    scope.current_user && ::Topic.voted(object.topic, scope.current_user)
  end

  def last_answered_at
    object.topic.last_answered_at
  end

  def include_last_answered_at?
    qa_enabled
  end

  def last_commented_on
    object.topic.last_commented_on
  end

  def include_last_commented_on?
    qa_enabled
  end

  def answer_count
    object.topic.answer_count
  end

  def include_answer_count?
    qa_enabled
  end

  def comment_count
    object.topic.comment_count
  end

  def include_comment_count?
    qa_enabled
  end

  def last_answer_post_number
    object.topic.last_answer_post_number
  end

  def include_last_answer_post_number?
    qa_enabled
  end

  def last_answerer
    ::BasicUserSerializer.new(object.topic.last_answerer, scope: scope, root: false)
  end

  def include_last_answerer
    qa_enabled
  end
end
