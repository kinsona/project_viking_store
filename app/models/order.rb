class Order < ActiveRecord::Base
  belongs_to :user
  accepts_nested_attributes_for :user

  has_many :order_contents, :class_name => "OrderContents", :dependent => :destroy
  accepts_nested_attributes_for :order_contents, :reject_if => proc { |attributes| attributes['quantity'].to_i < 0 }, :allow_destroy => true

  has_many :products, :through => :order_contents
  has_many :categories, :through => :products

  belongs_to :billing_address, :class_name => 'Address', :foreign_key => :billing_id
  belongs_to :shipping_address, :class_name => 'Address', :foreign_key => :shipping_id

  belongs_to :billing_card, :class_name => 'CreditCard', :foreign_key => :billing_card_id
  accepts_nested_attributes_for :billing_card, :reject_if => proc { |attributes| attributes.values.include?("") }, :allow_destroy => true


  validates :billing_address, :presence => { message: "is missing!"}, if: :checkout_date
  validates :shipping_address, :presence => { message: "is missing!"}, if: :checkout_date
  validates :order_contents, :presence => { message: "are empty!"}, if: :checkout_date



# Storefront methods
def update_quantity(product_id, amount)
  self.order_contents.where(:product_id => product_id).first.increase_quantity(amount)
end



# Portal methods
  def self.get_index_data(user_id = nil)

    orders = Order.order(:id).limit(100)

    orders = orders.where(:user_id => user_id) if user_id


    orders.map do |order|
      {
        :relation => order,
        :user => order.user,
        :address => order.shipping_address,
        :quantity => order.count_total_quantity,
        :order_value => order.calculate_order_value,
        :status => order.define_status,
        :date_placed => order.checkout_date
      }
    end

  end


  def count_total_quantity
    self.order_contents.sum(:quantity)
  end


  def calculate_order_value
    self.products.sum("order_contents.quantity * products.price")
  end


  def define_status
    if self.checkout_date
      'PLACED'
    else
      'UNPLACED'
    end
  end


  def get_card_last_4
    self.billing_card.card_number if self.billing_card_id
  end


  def build_contents_table_data
    order_contents = self.order_contents.all.order(:product_id)

    order_contents.map do |content_row|
      {
        :relation => content_row,
        :product_id => content_row.product_id,
        :product_name => content_row.product.name,
        :quantity => content_row.quantity,
        :price => content_row.product.price,
        :total_price => content_row.quantity * content_row.product.price
      }
    end

  end


  def update_checkout_date(new_status)
    if new_status == "PLACED" && self.checkout_date.nil?
      DateTime.now
    elsif new_status =="UNPLACED"
      nil
    end
  end




# Dashboard methods

  def self.within_days(day_range = nil, last_day = DateTime.now)
    if day_range.nil?
      where("checkout_date IS NOT NULL")
    else
      where("checkout_date BETWEEN ? AND ?", last_day - day_range.days, last_day)
    end
  end


  def self.count_orders(day_range = nil, last_day = DateTime.now)
    Order.within_days(day_range, last_day).count
  end



  # for all new orders within past x days
  def self.calc_revenue(day_range = nil, last_day = DateTime.now)
    Order.within_days(day_range, last_day).inject(0) do |sum, o|
      sum += o.products.sum("products.price * order_contents.quantity")
    end
  end



  # Pulls stats for a period of time.  Optional arguments for 1) the number of days
  # to include in the range, and 2) the starting date from which to count backwards/
  # Defaults to selecting all days in the database and using the current time as the
  # Starting point.



  def self.order_stats_by_day_range(number_of_days = nil, last_day = DateTime.now)

    base_query = Order.select("COUNT(DISTINCT orders.id) AS count,
                                SUM(products.price * order_contents.quantity) AS revenue,
                                SUM(products.price * order_contents.quantity) / COUNT(DISTINCT orders.id) AS average").
                        joins("JOIN order_contents ON orders.id = order_contents.order_id
                              JOIN products ON order_contents.product_id = products.id")

    filter_query = base_query.within_days(number_of_days, last_day).each.first

    {'Number of Orders' => filter_query.count,
    'Total Revenue' => filter_query.revenue,
    'Average Order Value' => filter_query.average,
    'Largest Order Value' => Order.largest_order(number_of_days, last_day)
    }

  end


  def self.largest_order(number_of_days, start)
    base_query = Order.select("orders.id,
                  SUM(products.price * order_contents.quantity) AS order_total").
            joins("JOIN order_contents ON orders.id = order_contents.order_id
                  JOIN products ON order_contents.product_id = products.id").
            group("orders.id").
            order("SUM(products.price * order_contents.quantity) DESC")

    if number_of_days.nil?
      full_query = base_query.where("orders.checkout_date IS NOT NULL").first
    else
      full_query = base_query.where("orders.checkout_date BETWEEN ? AND ?", start - number_of_days.days, start).first
    end


    if full_query.nil?
      max_order = nil
    else
      max_order = full_query.order_total
    end

    max_order

  end


end