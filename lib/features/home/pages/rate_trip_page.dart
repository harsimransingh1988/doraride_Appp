import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

const _kThemeBlue = Color(0xFF180D3B);
const _kThemeGreen = Color(0xFF279C56);

class RateTripPage extends StatefulWidget {
  final String bookingId;
  final String tripId;
  final String recipientId; // person we are rating
  final String recipientName; // their display name
  final String role; // 'rider' (rate driver) or 'driver' (rate rider)

  const RateTripPage({
    super.key,
    required this.bookingId,
    required this.tripId,
    required this.recipientId,
    required this.recipientName,
    required this.role,
  });

  @override
  State<RateTripPage> createState() => _RateTripPageState();
}

class _RateTripPageState extends State<RateTripPage>
    with SingleTickerProviderStateMixin {
  double _rating = 5;
  final TextEditingController _commentController = TextEditingController();
  bool _submitting = false;

  bool _hasExistingReview = false;
  bool _loadingInitial = true;

  // --- NEW: character counter state ---
  static const int _maxChars = 500;
  int _commentLength = 0;

  // Quick emoji suggestions row
  final List<String> _quickEmojis = const ['😊', '👍', '🚗', '✨', '😐'];

  /// Try to resolve a nice display name for the *author* of the review.
  Future<String> _resolveAuthorName(User user) async {
    String result = '';

    // 1) Try Firestore users/{uid} for first/last name or displayName
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

      if (snap.exists) {
        final data = snap.data() ?? {};
        final first = (data['firstName'] ?? '').toString().trim();
        final last = (data['lastName'] ?? '').toString().trim();
        final full = [first, last].where((s) => s.isNotEmpty).join(' ');

        if (full.isNotEmpty) return full;

        final docDisplay = (data['displayName'] ?? '').toString().trim();
        if (docDisplay.isNotEmpty) return docDisplay;
      }
    } catch (_) {
      // ignore and use fallbacks below
    }

    // 2) Fallback to FirebaseAuth displayName
    if ((user.displayName ?? '').trim().isNotEmpty) {
      return user.displayName!.trim();
    }

    // 3) Fallback to email (before @)
    if ((user.email ?? '').trim().isNotEmpty) {
      final email = user.email!.trim();
      final atIndex = email.indexOf('@');
      if (atIndex > 0) {
        return email.substring(0, atIndex);
      }
      return email;
    }

    // 4) Last resort
    return 'Rider';
  }

  /// NEW: load existing review so we can EDIT instead of always creating.
  Future<void> _loadExistingReviewIfAny() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _loadingInitial = false;
      });
      return;
    }

    try {
      final reviewDocId = '${widget.tripId}_${user.uid}_${widget.recipientId}';
      final snap = await FirebaseFirestore.instance
          .collection('reviews')
          .doc(reviewDocId)
          .get();

      if (snap.exists && snap.data() != null) {
        final data = snap.data()!;
        final r = data['rating'];
        final c = (data['comment'] ?? '').toString();

        setState(() {
          _hasExistingReview = true;
          if (r is int || r is double) {
            _rating = (r as num).toDouble().clamp(1, 5);
          }
          _commentController.text = c;
          _commentLength = _commentController.text.characters.length;
          _loadingInitial = false;
        });
      } else {
        setState(() {
          _loadingInitial = false;
        });
      }
    } catch (_) {
      setState(() {
        _loadingInitial = false;
      });
    }
  }

  void _onCommentChanged() {
    setState(() {
      _commentLength = _commentController.text.characters.length;
    });
  }

  @override
  void initState() {
    super.initState();
    _commentController.addListener(_onCommentChanged);
    _loadExistingReviewIfAny();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please sign in to leave a review.')),
      );
      return;
    }

    if (_rating <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a rating.')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      // Resolve the name of the *author* (the one leaving the review)
      final authorName = await _resolveAuthorName(user);

      final reviewerId = user.uid;

      // Deterministic doc ID: one review per (trip + reviewer + recipient)
      final reviewDocId = '${widget.tripId}_${reviewerId}_${widget.recipientId}';
      final reviewRef =
          FirebaseFirestore.instance.collection('reviews').doc(reviewDocId);

      final reviewData = {
        'authorId': reviewerId,
        'authorName': authorName, // used on profile page
        'recipientId': widget.recipientId,
        'recipientName': widget.recipientName,
        'tripId': widget.tripId,
        'bookingId': widget.bookingId,
        'rating': _rating.round(), // store as int
        'comment': _commentController.text.trim(),
        'role': widget.role, // 'rider' or 'driver'
        'updatedAt': FieldValue.serverTimestamp(),
      };

      final existing = await reviewRef.get();
      if (!existing.exists) {
        reviewData['createdAt'] = FieldValue.serverTimestamp();
      }

      // Create or update review document
      await reviewRef.set(reviewData, SetOptions(merge: true));

      // Mark rating flags on booking mirrors so we don't nag again
      if (widget.bookingId.isNotEmpty) {
        if (widget.role == 'rider') {
          // Rider rating the driver: update rider's own my_bookings mirror
          await FirebaseFirestore.instance
              .collection('users')
              .doc(reviewerId)
              .collection('my_bookings')
              .doc(widget.bookingId)
              .set(
            {
              'isRiderRated': true,
              'needsRiderReview': false,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        } else if (widget.role == 'driver') {
          // Driver rating the rider: update rider's mirror if possible
          final riderId = widget.recipientId;
          if (riderId.isNotEmpty) {
            await FirebaseFirestore.instance
                .collection('users')
                .doc(riderId)
                .collection('my_bookings')
                .doc(widget.bookingId)
                .set(
              {
                'isDriverRated': true,
                'updatedAt': FieldValue.serverTimestamp(),
              },
              SetOptions(merge: true),
            );
          }
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_hasExistingReview
              ? 'Review updated.'
              : 'Review submitted. Thank you!'),
        ),
      );

      Navigator.of(context).pop();
    } on FirebaseException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Failed to submit review: [${e.code}] ${e.message ?? 'Unknown error'}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to submit review: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  @override
  void dispose() {
    _commentController.removeListener(_onCommentChanged);
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name =
        widget.recipientName.isEmpty ? 'this user' : widget.recipientName;

    final remaining = (_maxChars - _commentLength).clamp(0, _maxChars);

    return Scaffold(
      backgroundColor: _kThemeGreen,
      appBar: AppBar(
        backgroundColor: _kThemeBlue,
        foregroundColor: Colors.white,
        title: Text(_hasExistingReview ? 'Edit review for $name' : 'Rate $name'),
      ),
      body: SafeArea(
        child: _loadingInitial
            ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _hasExistingReview
                          ? 'Update your review for $name'
                          : 'How was your trip with $name?',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_hasExistingReview)
                      const Text(
                        'You can adjust the stars or edit your comment.',
                        style: TextStyle(
                          color: Colors.white70,
                        ),
                      ),
                    const SizedBox(height: 24),

                    // Stars row
                    Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(5, (i) {
                          final starIndex = i + 1;
                          final filled = starIndex <= _rating;
                          return IconButton(
                            onPressed: () {
                              setState(() {
                                _rating = starIndex.toDouble();
                              });
                            },
                            icon: Icon(
                              filled ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                              size: 40,
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // --- NEW: pretty comment box with emojis, counter, animation ---
                    Expanded(
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeInOut,
                        alignment: Alignment.topCenter,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            // emphasise rounded TOP corners
                            borderRadius: const BorderRadius.only(
                              topLeft: Radius.circular(18),
                              topRight: Radius.circular(18),
                              bottomLeft: Radius.circular(10),
                              bottomRight: Radius.circular(10),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.06),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // Emoji quick reactions row
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  children: [
                                    const Text(
                                      'Quick reaction:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: _kThemeBlue,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ..._quickEmojis.map(
                                      (emoji) => Padding(
                                        padding:
                                            const EdgeInsets.symmetric(horizontal: 2.0),
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(20),
                                          onTap: () {
                                            final text = _commentController.text;
                                            final separator =
                                                text.isEmpty || text.endsWith(' ')
                                                    ? ''
                                                    : ' ';
                                            _commentController.text =
                                                '$text$separator$emoji';
                                            _commentController.selection =
                                                TextSelection.fromPosition(
                                              TextPosition(
                                                  offset:
                                                      _commentController.text.length),
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade100,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              emoji,
                                              style: const TextStyle(fontSize: 18),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Divider(height: 1),

                              // The text field itself
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                                  child: TextField(
                                    controller: _commentController,
                                    maxLines: null,
                                    minLines: 4,
                                    keyboardType: TextInputType.multiline,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.black87,
                                    ),
                                    maxLength: _maxChars,
                                    // hide default Flutter counter
                                    buildCounter: (
                                      context, {
                                      required int currentLength,
                                      required bool isFocused,
                                      int? maxLength,
                                    }) {
                                      return const SizedBox.shrink();
                                    },
                                    decoration: const InputDecoration(
                                      hintText:
                                          'Driver was polite? Ride was comfortable?\n'
                                          'Anything we should improve?',
                                      hintStyle: TextStyle(
                                        color: Colors.black54,
                                        fontSize: 15,
                                      ),
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                              ),

                              // Character counter row
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 8),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.edit_note_outlined,
                                      size: 18,
                                      color: _kThemeBlue,
                                    ),
                                    const SizedBox(width: 6),
                                    const Text(
                                      'Optional comment',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _kThemeBlue,
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '$remaining / $_maxChars',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: remaining <= 20
                                            ? Colors.redAccent
                                            : Colors.black.withOpacity(0.55),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: _kThemeBlue,
                          foregroundColor: Colors.white,
                          shape: const StadiumBorder(),
                        ),
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Text(
                                _hasExistingReview
                                    ? 'Update Review'
                                    : 'Submit Review',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
